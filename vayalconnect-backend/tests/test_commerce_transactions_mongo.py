"""Real replica-set commerce regressions. All users/data are isolated test fixtures.
Only external government/Razorpay providers are mocked; database writes are real.
"""
import asyncio
import os
import uuid
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, patch
import httpx
import pytest
from bson import ObjectId
from cryptography.fernet import Fernet
from motor.motor_asyncio import AsyncIOMotorClient
from app.main import app
from app.core.database import get_database, Database
from app.core.security import create_access_token
from app.core.exceptions import ProductOutOfStockError, NotFoundError, PaymentVerificationFailedError
from app.repositories.products import ProductRepository
from app.services.order_service import OrderService
from app.services.payment_service import PaymentService
from app.services.pricing_service import CommissionService
from app.services.address_service import AddressService
from app.services.delivery_service import distance_km
from tests.conftest import complete_farmer

pytestmark = [pytest.mark.asyncio, pytest.mark.skipif(os.environ.get('VAYALCONNECT_RUN_MONGO_TESTS')!='1',reason='Opt-in isolated replica-set verification')]

async def test_transactional_commerce_and_address_ownership():
    uri=os.environ.get('VAYALCONNECT_TEST_MONGO_URI','mongodb://127.0.0.1:27019/?replicaSet=vayal_verification')
    assert uri.startswith('mongodb://127.0.0.1:27019/'), 'This test is confined to the isolated local replica set.'
    client=AsyncIOMotorClient(uri,tz_aware=True,serverSelectionTimeoutMS=5000)
    name='vayal_tx_checks_'+uuid.uuid4().hex
    db=client[name]
    ids={r:ObjectId() for r in ['FARMER','BUYER','OTHER','ADMIN']}
    now=datetime.now(timezone.utc)
    try:
        store=Database();store.db=db;await store.create_indexes()
        with patch('app.core.security.settings.ENCRYPTION_KEY',Fernet.generate_key().decode()):
            for n,(role,identifier) in enumerate(ids.items()):
                await db.users.insert_one({'_id':identifier,'name':role,'email':role.lower()+'@example.invalid','phone':f'987654321{n}',
                    'role':'BUYER' if role=='OTHER' else role,'is_active':True,'email_verified':True})
            await db.farmer_profiles.insert_one({'user_id':ids['FARMER'],**complete_farmer()})
            for role in ['BUYER','OTHER']:await db.buyer_profiles.insert_one({'user_id':ids[role]})
            price={'product_name':'Wheat','category':'Grains','quantity_available':3,'quantity_unit':'KG','quality_grade':'A',
                'location':'Test district','market':'Test market','farmer_id':str(ids['FARMER']),
                'farmer_payout_per_unit_paise':1001,'pricing_mode':'FARMER_SELECTED','harvest_date':now.date().isoformat()}
            pid=await ProductRepository(db).create(price)
            buyer,other,farmer=map(str,[ids['BUYER'],ids['OTHER'],ids['FARMER']])
            await CommissionService(db).update_commission(1000,str(ids['ADMIN']))
            service=OrderService(db)
            # Concurrent real transactions cannot reserve more than three units.
            outcomes=await asyncio.gather(*(service.create_order(buyer,pid,1,idempotency_key=uuid.uuid4().hex) for _ in range(6)),return_exceptions=True)
            orders=[o for o in outcomes if isinstance(o,dict)]
            assert len(orders)==3, outcomes
            assert await db.orders.count_documents({})==3
            assert (await db.products.find_one({'_id':ObjectId(pid)}))['quantity_available']==0
            assert all(o['buyer_total_paise']==1101 and o['commission_total_paise']==100 and o['farmer_total_payout_paise']==1001 for o in orders)
            # Duplicate concurrent cancellation restores exactly one unit once.
            order=orders[0]
            await asyncio.gather(*(service.cancel_order(order['id'],buyer,'BUYER','test cancellation') for _ in range(3)))
            assert (await db.products.find_one({'_id':ObjectId(pid)}))['quantity_available']==1
            # Rollback a persisted order if the final operation fails.
            with patch.object(service.audit_service,'log',AsyncMock(side_effect=RuntimeError('isolated audit failure'))):
                with pytest.raises(RuntimeError):await service.create_order(buyer,pid,1,idempotency_key=uuid.uuid4().hex)
            assert await db.orders.count_documents({})==3
            assert (await db.products.find_one({'_id':ObjectId(pid)}))['quantity_available']==1
            await CommissionService(db).update_commission(1500,str(ids['ADMIN']))
            key=uuid.uuid4().hex
            duplicate=await asyncio.gather(*(service.create_order(buyer,pid,1,idempotency_key=key) for _ in range(3)))
            assert len({o['id'] for o in duplicate})==1
            new=duplicate[0]; assert new['buyer_total_paise']==1151
            assert (await db.orders.find_one({'_id':ObjectId(order['id'])}))['buyer_total_paise']==1101
            # Real payment persistence; only gateway HTTP is replaced with synthetic test responses.
            pay=PaymentService(db)
            with patch('app.services.payment_service.razorpay_payment.create_order',AsyncMock(return_value={'razorpay_order_id':'order_isolated'})) as create:
                first=await pay.create_payment(new['id'],buyer); second=await pay.create_payment(new['id'],buyer)
                assert first['razorpay_order_id']==second['razorpay_order_id'];create.assert_awaited_once()
            gateway={'id':'pay_isolated','order_id':'order_isolated','amount':1151,'currency':'INR','status':'captured'}
            with patch('app.services.payment_service.razorpay_payment.verify_payment_signature',AsyncMock(return_value=True)),patch('app.services.payment_service.razorpay_payment.fetch_payment',AsyncMock(return_value=gateway)):
                with pytest.raises(PaymentVerificationFailedError):
                    with patch('app.services.payment_service.razorpay_payment.fetch_payment',AsyncMock(return_value=gateway|{'amount':1})):
                        await pay.verify_payment(new['id'],'order_isolated','pay_isolated','synthetic',buyer)
                result=await pay.verify_payment(new['id'],'order_isolated','pay_isolated','synthetic',buyer)
                assert result['payment_verified'] and result['order_status']=='PAID'
                assert (await pay.verify_payment(new['id'],'order_isolated','pay_isolated','synthetic',buyer))['payment_verified']
            assert await db.payouts.count_documents({'order_id':ObjectId(new['id'])})==1
            assert (await db.products.find_one({'_id':ObjectId(pid)}))['quantity_available']==0
            for status in ['CONFIRMED','PROCESSING','COMPLETED']:
                await service.update_order_status(new['id'],status,farmer,'FARMER')
            assert (await db.orders.find_one({'_id':ObjectId(new['id'])}))['order_status']=='COMPLETED'
            # Concurrent commission edits serialize; only one global rate remains active.
            await asyncio.gather(*(CommissionService(db).update_commission(rate,str(ids['ADMIN'])) for rate in [500,1000,1500]))
            assert await db.commission_configs.count_documents({'status':'ACTIVE'})==1
            assert await db.commission_configs.count_documents({})==5
            # A real expired reservation releases inventory once, including repeated sweepers.
            await db.products.update_one({'_id':ObjectId(pid)},{'$inc':{'quantity_available':2},'$set':{'status':'ACTIVE'}})
            expiring=await service.create_order(buyer,pid,1,idempotency_key=uuid.uuid4().hex)
            assert expiring['reservation_expires_at']>now
            await db.orders.update_one({'_id':ObjectId(expiring['id'])},{'$unset':{'reservation_expires_at':''}})
            await store.create_indexes()
            migrated=await db.orders.find_one({'_id':ObjectId(expiring['id'])})
            assert migrated['reservation_expires_at']>datetime.now(timezone.utc)
            assert migrated['buyer_total_paise']==expiring['buyer_total_paise']

            await db.orders.update_one({'_id':ObjectId(expiring['id'])},{'$set':{'reservation_expires_at':now-timedelta(minutes=1)}})
            await asyncio.gather(service.expire_reservations(),service.expire_reservations())
            assert (await db.orders.find_one({'_id':ObjectId(expiring['id'])}))['order_status']=='CANCELLED'
            assert (await db.products.find_one({'_id':ObjectId(pid)}))['quantity_available']==2
            # A late verified test capture is audited without resurrecting cancelled stock/order.
            late=await service.create_order(buyer,pid,1,idempotency_key=uuid.uuid4().hex)
            with patch('app.services.payment_service.razorpay_payment.create_order',AsyncMock(return_value={'razorpay_order_id':'order_late'})):
                await pay.create_payment(late['id'],buyer)
            await service.cancel_order(late['id'],buyer,'BUYER','Cancelled before capture')
            gateway_late={'id':'pay_late','order_id':'order_late','amount':late['buyer_total_paise'],'currency':'INR','status':'captured'}
            with patch('app.services.payment_service.razorpay_payment.verify_payment_signature',AsyncMock(return_value=True)),patch('app.services.payment_service.razorpay_payment.fetch_payment',AsyncMock(return_value=gateway_late)):
                settled=await pay.verify_payment(late['id'],'order_late','pay_late','synthetic',buyer)
            assert settled['order_status']=='CANCELLED'
            assert (await db.orders.find_one({'_id':ObjectId(late['id'])}))['refund_required'] is True
            assert await db.payouts.count_documents({'order_id':ObjectId(late['id'])})==0
            assert (await db.products.find_one({'_id':ObjectId(pid)}))['quantity_available']==2

            # Offline key rotation preserves plaintext and rolls back every field on corrupt data.
            from scripts.rotate_security_keys import rotate_bank_records
            from app.core.security import settings
            from cryptography.fernet import InvalidToken
            old_key=settings.ENCRYPTION_KEY; next_key=Fernet.generate_key().decode()
            before=await db.farmer_profiles.find_one({'user_id':ids['FARMER']})
            assert await rotate_bank_records(db,old_key,next_key,dry_run=True)==1
            assert (await db.farmer_profiles.find_one({'user_id':ids['FARMER']}))['bank_account_number']==before['bank_account_number']
            assert await rotate_bank_records(db,old_key,next_key)==1
            rotated=await db.farmer_profiles.find_one({'user_id':ids['FARMER']})
            assert Fernet(next_key.encode()).decrypt(rotated['bank_account_number'].encode())==b'123456789012'
            with pytest.raises(InvalidToken):Fernet(old_key.encode()).decrypt(rotated['bank_account_number'].encode())
            # Restore the isolated fixture key, then add a malformed profile to prove atomic rollback.
            await rotate_bank_records(db,next_key,old_key)
            corrupt=await db.farmer_profiles.insert_one({'user_id':ObjectId(),'bank_account_number':'invalid-ciphertext'})
            before=await db.farmer_profiles.find_one({'user_id':ids['FARMER']})
            with pytest.raises(InvalidToken):await rotate_bank_records(db,old_key,next_key)
            assert (await db.farmer_profiles.find_one({'user_id':ids['FARMER']}))['bank_account_number']==before['bank_account_number']
            await db.farmer_profiles.delete_one({'_id':corrupt.inserted_id})
            # Addresses are scoped to authenticated user, GPS stays separate from postal address.
            from app.schemas.address import SavedAddress
            address=SavedAddress(recipient_name='Test buyer',phone='9876543210',building='10 Test house',street='Test street',locality='Test locality',city='Test town',state='Tamil Nadu',postal_code='625001',coordinates={'latitude':9.94,'longitude':78.14},is_default=True)
            addresses=AddressService(db)
            saved=await addresses.save(buyer,address)
            aid=saved['id']
            with pytest.raises(NotFoundError):await addresses.save(other,address,aid)
            assert (await addresses.list(other))==[]
            updated=await addresses.save(buyer,address.model_copy(update={'building':'11 Test house','coordinates':None}),aid)
            assert updated['coordinates'] is None
            await addresses.delete(buyer,aid);assert (await addresses.list(buyer))==[]
            # API role and ownership checks remain in force around the real DB.
            app.dependency_overrides[get_database]=lambda:db
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url='http://isolated-test') as api:
                headers=lambda role:{'Authorization':'Bearer '+create_access_token({'sub':str(ids[role]),'role':role})}
                assert (await api.get('/api/v1/orders/'+new['id'],headers=headers('OTHER'))).status_code==404
                assert (await api.get('/api/v1/admin/dashboard',headers=headers('BUYER'))).status_code==403
                assert (await api.put('/api/v1/users/me/location',json={'latitude':91,'longitude':0},headers=headers('BUYER'))).status_code==422
                # Real product create/edit/deactivate contracts, including stock rollback and owner checks.
                payload={'product_name':'Wheat','category':'Grains','quantity':4,'quantity_unit':'KG','quality_grade':'A',
                    'location':'Test district','market':'Test market','harvest_date':now.date().isoformat(),'selling_price_per_unit_paise':1001}
                with patch('app.services.pricing_service.market_price_provider.get_market_price',AsyncMock(return_value=None)):
                    response=await api.post('/api/v1/products/',json=payload,headers=headers('FARMER'))
                assert response.status_code==201,response.text
                created=response.json()['data']['product_id']
                visible=await api.get('/api/v1/products/'+created,headers=headers('BUYER'))
                assert visible.status_code==200 and visible.json()['data']['product_name']=='Wheat'
                invalid=await api.put('/api/v1/products/'+created,json={'stock_adjustment':-5,'selling_price_per_unit_paise':2000},headers=headers('FARMER'))
                assert invalid.status_code==422,invalid.text
                assert (await db.products.find_one({'_id':ObjectId(created)}))['quantity_available']==4
                assert (await db.products.find_one({'_id':ObjectId(created)}))['farmer_payout_per_unit_paise']==1001
                assert (await api.put('/api/v1/products/'+created,json={'stock_adjustment':2,'selling_price_per_unit_paise':2000},headers=headers('FARMER'))).status_code==200
                assert (await db.products.find_one({'_id':ObjectId(created)}))['quantity_available']==6
                assert (await api.put('/api/v1/products/'+created,json={'stock_adjustment':1},headers=headers('BUYER'))).status_code==403
                assert (await api.delete('/api/v1/products/'+created,headers=headers('FARMER'))).status_code==200
                assert (await api.get('/api/v1/products/'+created,headers=headers('BUYER'))).status_code==404
                # Crop image validation compresses actual bytes, restricts ownership and visibility.
                from io import BytesIO
                from PIL import Image
                raw=BytesIO();Image.new('RGB',(200,200),color='green').save(raw,format='PNG')
                image=await api.post('/api/v1/media',files={'file':('fixture.png',raw.getvalue(),'image/png')},headers=headers('FARMER'))
                assert image.status_code==201,image.text
                image_url=image.json()['data']['image_url']
                assert (await api.get(image_url,headers=headers('FARMER'))).headers['content-type']=='image/jpeg'
                assert (await api.get(image_url,headers=headers('BUYER'))).status_code==404
                assert (await api.post('/api/v1/media',files={'file':('fixture.txt',b'not an image','text/plain')},headers=headers('FARMER'))).status_code==422

                payouts_response=await api.get('/api/v1/payouts/',headers=headers('ADMIN'))
                assert payouts_response.status_code==200,payouts_response.text
                assert payouts_response.json()['data']['items'][0]['product_name']=='Wheat'
                assert payouts_response.json()['data']['items'][0]['commission_total_paise']==150
                for period in ['today','month','year']:
                    response=await api.get('/api/v1/admin/dashboard?period='+period,headers=headers('ADMIN'))
                    assert response.status_code==200,response.text
                    assert response.json()['data']['total_platform_commission_paise']==150
    finally:
        app.dependency_overrides.pop(get_database,None)
        assert name.startswith('vayal_tx_checks_')
        await client.drop_database(name);client.close()

async def test_distance_and_unavailable_estimates():
    from app.services.delivery_service import estimate_delivery
    assert distance_km({'latitude':0,'longitude':0},{'latitude':0,'longitude':1})==pytest.approx(111.195,rel=.001)
    assert estimate_delivery(None,None,None,'DELIVERY')['available'] is False
    assert estimate_delivery({'latitude':9.92,'longitude':78.12},{'latitude':9.94,'longitude':78.14},None,'DELIVERY')['distance_type']=='STRAIGHT_LINE'


async def test_concurrent_initial_admin_provisioning_preserves_single_account():
    from scripts.seed_admin import _provision_admin
    from app.core.transactions import run_locked_transaction
    from app.core.security import verify_password
    from app.core.exceptions import ValidationError
    client=AsyncIOMotorClient('mongodb://127.0.0.1:27019/?replicaSet=vayal_verification',serverSelectionTimeoutMS=5000)
    name='vayal_tx_bootstrap_'+uuid.uuid4().hex;db=client[name]
    try:
        store=Database();store.db=db;await store.create_indexes()
        async def provision(email,phone):
            async def operation():return await _provision_admin(db,email,'IsolatedStrongPassword123!',phone)
            return await run_locked_transaction(db,"provision_locks","initial-administrator",operation)
        outcomes=await asyncio.gather(provision('admin1@example.invalid','9876543210'),provision('admin2@example.invalid','9876543211'),return_exceptions=True)
        assert sum(isinstance(o,dict) for o in outcomes)==1
        assert sum(isinstance(o,ValidationError) for o in outcomes)==1
        assert await db.users.count_documents({'role':'ADMIN'})==1
        account=await db.users.find_one({'role':'ADMIN'})
        assert verify_password('IsolatedStrongPassword123!',account['password_hash'])
        assert account['password_hash']!='IsolatedStrongPassword123!'
        original_hash=account['password_hash']
        async def repeat():return await _provision_admin(db,account['email'],'DifferentStrongPassword123!',account['phone'])
        result=await run_locked_transaction(db,"provision_locks","initial-administrator",repeat)
        assert result['existing'] is True
        assert (await db.users.find_one({'_id':account['_id']}))['password_hash']==original_hash
    finally:
        assert name.startswith('vayal_tx_bootstrap_');await client.drop_database(name);client.close()
