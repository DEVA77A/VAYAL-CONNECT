"""Offline, private-terminal rotation. Preserve bank plaintext and account IDs.
Requires an Atlas backup and paused application writers. Never logs key values.
"""
import argparse
import asyncio
import os
import secrets
import subprocess
import sys
from pathlib import Path
from cryptography.fernet import Fernet
from dotenv import dotenv_values
from motor.motor_asyncio import AsyncIOMotorClient
from app.core.transactions import run_transaction, collection

BANK_FIELDS = ("bank_account_holder_name", "bank_name", "bank_account_number", "bank_ifsc", "upi_id")

async def rotate_bank_records(db, old_key, new_key, dry_run=False):
    old, new = Fernet(old_key.encode()), Fernet(new_key.encode())
    async def operation():
        profiles = collection(db, "farmer_profiles")
        rows = await profiles.find({}).limit(1001).to_list(1001)
        if len(rows) > 1000:
            raise RuntimeError("Rotation exceeds bounded batch; coordinate a migration for larger databases.")
        count = 0
        for row in rows:
            changes = {}
            for field in BANK_FIELDS:
                if row.get(field):
                    # Unknown/invalid ciphertext aborts the transaction, preserving all records.
                    plaintext = old.decrypt(row[field].encode())
                    changes[field] = new.encrypt(plaintext).decode()
            if changes:
                count += 1
                if not dry_run:
                    await profiles.update_one({"_id": row["_id"]}, {"$set": changes})
        return count
    return await run_transaction(db, operation)

def write_private_file(path, content):
    path = Path(path).resolve()
    if not path.name.endswith('.env'):
        raise ValueError("Use a private .env file excluded from Git.")
    # O_EXCL refuses to overwrite any existing recovery/key file.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(descriptor)
    if os.name == 'nt':
        owner = subprocess.check_output(['whoami'], text=True).strip()
        result = subprocess.run(['icacls', str(path), '/inheritance:r', '/grant:r', owner + ':F'], capture_output=True)
        if result.returncode:
            raise RuntimeError("Could not restrict recovery-file permissions; no database change attempted.")
    path.write_text(content, encoding='utf-8')

async def run(args):
    config = {**dotenv_values('.env'), **os.environ}
    new_key = Fernet.generate_key().decode()
    if not args.dry_run:
        write_private_file(args.new_key_file, 'JWT_SECRET=' + secrets.token_urlsafe(48) + '\nENCRYPTION_KEY=' + new_key + '\n')
    client = AsyncIOMotorClient(config['MONGODB_URI'], serverSelectionTimeoutMS=15000)
    try:
        db = client[config.get('MONGODB_DATABASE', 'vayalconnect')]
        count = await rotate_bank_records(db, config['ENCRYPTION_KEY'], new_key, args.dry_run)
        print(('Dry run verified' if args.dry_run else 'Atomic rotation committed') + ': ' + str(count) + ' bank profiles.')
        if not args.dry_run:
            print('Install both values from the private recovery file in every backend environment BEFORE resuming writers. Preserve this file in your password manager.')
    finally:
        client.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--new-key-file', help='New private .env file; never overwritten')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise SystemExit('Use a private interactive terminal; shared log execution refused.')
    if not args.dry_run:
        if not args.new_key_file:
            raise SystemExit('--new-key-file is required for recovery.')
        if input('Confirm Atlas backup completed and ALL backend writers paused. Type ROTATE BANK KEY: ') != 'ROTATE BANK KEY':
            raise SystemExit('Rotation cancelled; database unchanged.')
    try:
        asyncio.run(run(args))
    except Exception as exc:
        raise SystemExit('Rotation could not complete (' + type(exc).__name__ + '). Keep any generated recovery file; restore/check the backup and configuration before resuming.') from None
