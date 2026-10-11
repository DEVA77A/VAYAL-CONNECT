"""One-time administrator provisioning, confined to a private interactive terminal.
No public registration, password arguments, password logging, or account promotion.
"""
import argparse
import asyncio
import secrets
import string
import sys
from getpass import getpass
from datetime import datetime, timezone
from app.core.database import connect_db, close_db, get_database
from app.core.security import hash_password
from app.core.transactions import run_locked_transaction, collection
from app.repositories.users import UserRepository
from app.repositories.pricing import PricingRepository
from app.services.audit_service import AuditService
from app.core.exceptions import ValidationError
from app.utils.validators import is_valid_email, is_valid_phone

async def seed_admin(admin_email=None, admin_password=None, admin_phone=None):
    await connect_db()
    try:
        db=get_database()
        async def operation():
            return await _provision_admin(db,admin_email,admin_password,admin_phone)
        result=await run_locked_transaction(db,"provision_locks","initial-administrator",operation)
        print('Administrator already exists; account and password preserved.' if result['existing'] else 'Administrator provisioned successfully.')
        print('Local administrator account ID: '+result['id'])
        return result
    finally:
        await close_db()

async def _provision_admin(db,email,password,phone):
    email=(email or '').strip().lower()
    if not is_valid_email(email) or not phone or not is_valid_phone(phone):
        raise ValidationError('Supply a valid administrator email and phone.')
    if not password or len(password)<16 or len(password.encode('utf-8'))>72 or not any(c.isupper() for c in password) or not any(c.isdigit() for c in password):
        raise ValidationError('Use a strong password of 16-72 bytes including uppercase and a digit.')
    users=UserRepository(db);pricing=PricingRepository(db)
    existing=await users.find_by_email(email)
    if existing:
        if existing.get('role')!='ADMIN':raise ValidationError('Provisioning cannot promote an ordinary account.')
        return {'id':existing['id'],'existing':True}
    if await collection(db,'users').find_one({'role':'ADMIN'},{'_id':1}):
        raise ValidationError('An administrator already exists. No account was created or overwritten. Use the existing account password reset flow.')
    if await users.find_by_phone(phone):raise ValidationError('Phone already registered; no account was changed.')
    identifier=await users.create({'name':'VayalConnect Admin','email':email,'phone':phone,'password_hash':hash_password(password),
        'address':'VayalConnect administration','area_location':'Administration','gender':'other','age':18,'role':'ADMIN',
        'email_verified':True,'is_active':True,'is_approved':True,'preferred_language':'en'})
    await AuditService(db).log(actor_id=identifier,actor_role='ADMIN',action='ADMIN_PROVISIONED',entity_type='user',entity_id=identifier)
    if not await pricing.get_active_commission():
        await pricing.create_commission_config({'commission_percentage_bps':2000,'effective_from':datetime.now(timezone.utc),'effective_until':None,'created_by':identifier,'status':'ACTIVE','version':1})
    # Retain the historical policy for compatibility; new orders use farmer-selected base prices.
    if not await pricing.get_active_policy():
        await pricing.create_policy({'name':'Default Policy','description':'Historical government-reference policy','farmer_payout_percentage_bps':7000,'buyer_price_percentage_bps':9000,'is_active':True,'version':1})
    return {'id':identifier,'existing':False}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description='Secure one-time administrator provisioning')
    parser.add_argument('--email',required=True);parser.add_argument('--phone',required=True)
    parser.add_argument('--generate-password',action='store_true',help='Generate a strong password displayed only in this private terminal; store in your password manager')
    args=parser.parse_args()
    if not sys.stdin.isatty() or not sys.stdout.isatty():raise SystemExit('Run in your own interactive terminal. Shared log output is refused.')
    generated=args.generate_password
    if generated:
        alphabet=string.ascii_letters+string.digits+'!@#%_-'
        password='A1'+''.join(secrets.choice(alphabet) for _ in range(30))
    else:
        password=getpass('Administrator password (hidden, 16-72 bytes): ')
        if password!=getpass('Confirm password (hidden): '):raise SystemExit('Passwords differ; no database changes made.')
    try:
        result=asyncio.run(seed_admin(args.email,password,args.phone))
        if generated and not result['existing']:print('Initial password (private terminal only; store securely): '+password)
    except ValidationError as error:
        raise SystemExit(error.detail) from None
