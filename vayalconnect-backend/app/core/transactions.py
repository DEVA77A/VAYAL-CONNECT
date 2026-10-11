"""MongoDB transactions for changes spanning inventory, orders, payments and payouts.

Atlas provides replica-set transactions. A standalone development MongoDB cannot
silently fall back to non-atomic commerce writes; use a local replica set.
"""
from contextvars import ContextVar
from functools import wraps

current_session = ContextVar("mongo_transaction_session", default=None)


class TransactionCollection:
    def __init__(self, collection):
        self.collection = collection

    def __getattr__(self, name):
        method = getattr(self.collection, name)
        if name not in {"find", "find_one", "aggregate", "insert_one", "update_one", "update_many",
                        "find_one_and_update", "delete_one", "count_documents"}:
            return method
        def call(*args, **kwargs):
            session = current_session.get()
            if session is not None:
                kwargs["session"] = session
            return method(*args, **kwargs)
        return call


def collection(db, name):
    return TransactionCollection(db[name])


async def run_transaction(db, operation):
    async with await db.client.start_session() as session:
        async def scoped(active_session):
            token = current_session.set(active_session)
            try:
                return await operation()
            finally:
                current_session.reset(token)
        return await session.with_transaction(scoped)


def transactional(method):
    @wraps(method)
    async def wrapped(self, *args, **kwargs):
        if current_session.get() is not None:
            return await method(self, *args, **kwargs)
        async def operation():
            return await method(self, *args, **kwargs)
        return await run_transaction(self.db, operation)
    return wrapped


def transactional_endpoint(method):
    @wraps(method)
    async def wrapped(*args, **kwargs):
        async def operation():
            return await method(*args, **kwargs)
        return await run_transaction(kwargs["db"], operation)
    return wrapped


async def run_locked_transaction(db, lock_name, lock_id, operation):
    """Create the serialization document before the transaction (first-use races).

    Concurrent upserts can raise DuplicateKey without a transaction retry label.
    A pre-existing document plus an actual revision increment avoids that gap.
    """
    from pymongo.errors import DuplicateKeyError
    try:
        await db[lock_name].update_one({'_id':lock_id}, {'$setOnInsert':{'revision':0}}, upsert=True)
    except DuplicateKeyError:
        pass  # Another caller created exactly this lock; no account/config is changed here.
    async def serialized():
        await collection(db, lock_name).update_one({'_id':lock_id}, {'$inc':{'revision':1}})
        return await operation()
    return await run_transaction(db, serialized)


def locked_transactional(lock_name, lock_id):
    def decorate(method):
        @wraps(method)
        async def wrapped(self, *args, **kwargs):
            async def operation():return await method(self, *args, **kwargs)
            return await run_locked_transaction(self.db, lock_name, lock_id, operation)
        return wrapped
    return decorate
