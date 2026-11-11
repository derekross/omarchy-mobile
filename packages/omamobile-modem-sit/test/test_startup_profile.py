# SPDX-License-Identifier: MIT
import env  # noqa: F401
import os,sys,tempfile,unittest,ast
from pathlib import Path
from unittest.mock import Mock,patch
HERE=Path(__file__).resolve().parent
import bringup,radio_power,paths,sit,service
class Tests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.dt=Path(self.tmp.name)/'compatible';self.dt.write_bytes(b'google,zumapro-komodo\0google,zumapro\0')
  self.settings=paths.config('/nonexistent');self.settings['network'].update(startup_profile='komodo-s5400',apn='fixture.invalid',attach_apn='fixture.invalid',ims_apn='ims',ims_first='no',internet_cid='1',ims='no',nr='on')
  self.events=[];self.client=Mock();self.client.request.side_effect=self.request;self.owner=Mock(client=self.client)
 def request(self,ident,payload=b'',**kw):
  self.events.append((ident,payload))
  if ident==0x0200:return bytes([1,0,1,2,5])+bytes(61)
  if ident==0x0701:return bytes([1,0,0,21])
  if ident==0x0602:return b'\0'
  return b''
 def run_start(self):
  with patch.object(radio_power,'COMPATIBLE',self.dt),patch.object(bringup,'radio',side_effect=lambda on:self.events.append(('AT',on))),patch.object(bringup,'radio_state',return_value=1)as state,patch.object(bringup,'activate',side_effect=lambda *a,**kw:self.events.append(('DATA',None))):
   bringup.start(self.owner,self.settings)
   return state.call_count
 def test_native_actual_start_order(self):
  self.assertEqual(self.run_start(),0)
  ids=[x[0]for x in self.events];self.assertEqual(ids[:4],[0x093f,0x0800,0x0200,0x0800]);self.assertIn(0x0603,ids);self.assertIn(0x0613,ids);self.assertEqual(ids.count(0x0800),3)
  self.assertEqual([p for i,p in self.events if i==0x0800],[bytes.fromhex(x)for x in ('020000000000','010000000000','020000000000')]);self.assertLess(ids.index(0x0613),max(i for i,v in enumerate(ids)if v==0x0800));self.assertNotIn('AT',ids)
 def test_default_retains_already_on_no_cycle(self):
  self.settings['network']['startup_profile']='default';self.assertEqual(self.run_start(),1);ids=[x[0]for x in self.events];self.assertEqual(ids[0],0x0200);self.assertNotIn(0x093f,ids);self.assertNotIn(0x0800,ids);self.assertNotIn('AT',ids)
 def test_default_unknown_state_preserves_cycle(self):
  self.settings['network']['startup_profile']='default'
  with patch.object(bringup,'radio_state',return_value=None),patch.object(radio_power,'COMPATIBLE',self.dt),patch.object(bringup,'radio',side_effect=lambda on:self.events.append(('AT',on))),patch.object(bringup,'activate'):
   bringup.start(self.owner,self.settings)
  self.assertEqual([p for i,p in self.events if i=='AT'],[False,True])
 def test_bad_profile_dt_apn_ip_no_requests(self):
  for field,value in [('startup_profile','unknown'),('apn','bad APN'),('ip_type','unknown')]:
   with self.subTest(field=field,value=value):
    old=self.settings['network'][field];self.settings['network'][field]=value
    with self.assertRaises(ValueError):self.run_start()
    self.assertEqual(self.events,[]);self.settings['network'][field]=old
  self.dt.write_bytes(b'google,cheetah\0')
  with self.assertRaises(ValueError):self.run_start()
  self.assertEqual(self.events,[])
 def test_stopped_before_setters(self):
  with patch.object(radio_power,'COMPATIBLE',self.dt),self.assertRaises(InterruptedError):bringup.start(self.owner,self.settings,lambda:True)
  self.assertEqual(self.events,[])
 def test_uncertain_initial_setters_never_retry(self):
  for fail in (0x093f,0x0800):
   self.events=[]
   def request(i,p=b'',**kw):
    self.events.append((i,p))
    if i==fail:raise TimeoutError('fixture uncertain')
    return b''
   self.client.request.side_effect=request
   with self.assertRaises(TimeoutError):self.run_start()
   self.assertEqual([i for i,p in self.events],[0x093f]if fail==0x093f else[0x093f,0x0800])
 def test_each_native_power_timeout_stops_without_retry(self):
  for position in (1,2,3):
   self.events=[];count=0
   def request(ident,payload=b'',**kwargs):
    nonlocal count
    if ident==0x0800:
     count+=1
     if count==position:
      self.events.append((ident,payload));raise TimeoutError('uncertain native power')
    return self.request(ident,payload,**kwargs)
   self.client.request.side_effect=request
   with self.assertRaises(TimeoutError):self.run_start()
   self.assertEqual(count,position)
   self.assertNotIn('DATA',[ident for ident,payload in self.events])
 def test_all_invalid_explicit_startup_inputs_refuse_before_any_request(self):
  invalid=[('attach_apn','bad APN'),('ims_apn','bad APN'),('ims_first','bad'),
           ('internet_cid','bad'),('internet_cid','0'),('internet_cid','2'),
           ('internet_cid','16'),('internet_cid','²')]
  invalid += [(key,'bad')for key in ('ims','ims_required','ims_pcscf_required','ims_pcscf_from_isim',
                                    'sim_timeout','register_timeout','carrier_manifest_timeout','ims_timeout')]
  for key,value in invalid:
   with self.subTest(key=key,value=value):
    old=self.settings['network'].get(key);self.settings['network'][key]=value;self.events=[]
    try:
     with self.assertRaises(ValueError):self.run_start()
     self.assertEqual(self.events,[])
    finally:
     if old is None:self.settings['network'].pop(key,None)
     else:self.settings['network'][key]=old
 def test_auto_empty_and_none_prevalidation_preserves_semantics(self):
  for value in ('auto','AUTO',''):
   for key in ('apn','attach_apn','ims_apn','ims_first','internet_cid'):self.settings['network'][key]=value
   bringup.validate_startup_inputs(self.settings['network'])
  for value in ('none','NONE'):
   self.settings['network']['attach_apn']=value
   bringup.validate_startup_inputs(self.settings['network'])
  self.client.request.assert_not_called()
 def test_valid_attach_none_full_start_skips_attach_setter(self):
  self.settings['network']['attach_apn']='none'
  with patch.object(bringup,'find_attach_bearer',return_value=None):self.run_start()
  self.assertNotIn(0x0603,[ident for ident,payload in self.events])
  self.assertEqual(sum(ident==0x0800 for ident,payload in self.events),3)
 def test_default_profile_does_not_run_new_prevalidator(self):
  self.settings['network']['startup_profile']='default'
  with patch.object(bringup,'validate_startup_inputs',side_effect=AssertionError('default validation changed')):self.run_start()
 def test_single_modem_typed_guard(self):
  sit.check(0x093f,payload=b'\0')
  for raw in (b'',b'\1',b'\0\0',bytearray(b'\0'),True,None):
   with self.subTest(raw=type(raw)),self.assertRaises(ValueError):sit.check(0x093f,payload=raw)
 def test_bool_power_guard(self):
  for val in (0,1,None,'on'):
   with self.assertRaises(ValueError):radio_power.native_radio(self.client,val)
  self.client.request.assert_not_called()
 def test_recovery_native_uses_same_transport(self):
  with patch.object(radio_power,'COMPATIBLE',self.dt),patch.object(service,'radio')as at,patch.object(service.cp,'state',return_value=0),self.assertRaises(service.UnconfirmedRelease):service.unconfirmed_release(self.client,'fixture',self.settings)
  at.assert_not_called();self.assertEqual(self.events[0],(0x0800,bytes.fromhex('010000000000')))
 def test_recovery_default_preserved(self):
  self.settings['network']['startup_profile']='default'
  with patch.object(service,'radio')as at,patch.object(service.cp,'state',return_value=0),self.assertRaises(service.UnconfirmedRelease):service.unconfirmed_release(self.client,'fixture',self.settings)
  at.assert_called_once_with(False)
 def test_all_recovery_callers_pass_context(self):
  tree=ast.parse((HERE.parent/'lib/service.py').read_text());calls=[n for n in ast.walk(tree)if isinstance(n,ast.Call)and isinstance(n.func,ast.Name)and n.func.id=='unconfirmed_release'];self.assertEqual(len(calls),3);self.assertTrue(all(len(n.args)==3 for n in calls))
 def test_runtime_radio_preserves_call_guard(self):
  obj=service.Service.__new__(service.Service);obj.client=self.client;obj.settings=self.settings;obj.live=lambda:False
  with patch.object(radio_power,'COMPATIBLE',self.dt),patch.object(service,'radio')as at:
   self.assertEqual(obj.dispatch(dict(action='radio',on=True)),dict(radio='on'));at.assert_not_called()
  self.assertEqual(self.events,[(0x0800,bytes.fromhex('020000000000'))]);self.events=[];obj.live=lambda:True
  with self.assertRaises(RuntimeError):obj.dispatch(dict(action='radio',on=False))
  self.assertEqual(self.events,[])
 def test_pin_puk_lock_refuses_before_attach(self):
  original=self.request
  for state in (2,3,4):
   self.events=[]
   def request(i,p=b'',**kw):
    if i==0x0200:
     self.events.append((i,p));return bytes([1,0,1,2,state])+bytes(61)
    return original(i,p,**kw)
   self.client.request.side_effect=request
   def wait(s,predicate,*args):
    if not predicate():predicate()
   with patch.object(bringup,'LOCK_GRACE',0),patch.object(bringup,'wait_for',side_effect=wait),self.assertRaises(RuntimeError):self.run_start()
   self.assertNotIn(0x0603,[i for i,p in self.events]);self.assertEqual(sum(i==0x0800 for i,p in self.events),1)
 def test_auto_and_empty_use_actual_carrier_selection_after_sim(self):
  for setting in ('auto','','AUTO'):
   self.events=[];self.settings['network']['apn']=setting
   original=self.request
   def request(i,p=b'',**kw):
    if i==0x0200:
     self.events.append((i,p));app=bytearray(63);app[:5]=bytes([2,5,0,1,42]);return bytes([1,0,1])+app
    if i==0x0400:
     self.events.append((i,p));return bytes([6])+b'123456'
    return original(i,p,**kw)
   self.client.request.side_effect=request
   def lookup(value):
    self.events.append(('CARRIER',None));return dict(apn='fixture.invalid',source='override')
   with patch.object(bringup.carrier_apn,'lookup',side_effect=lookup):self.run_start()
   ids=[i for i,p in self.events];self.assertEqual(ids[:5],[0x093f,0x0800,0x0200,0x0400,'CARRIER']);self.assertLess(ids.index('CARRIER'),ids.index(0x0603));self.assertLess(ids.index(0x0603),ids.index(0x0613))
   powers=[p for i,p in self.events if i==0x0800];self.assertEqual(powers,[bytes.fromhex(x)for x in ('020000000000','010000000000','020000000000')]);self.assertIn('DATA',ids);self.assertNotIn('AT',ids)
 def test_unknown_auto_carrier_never_invents_apn(self):
  self.settings['network'].update(apn='auto',attach_apn='auto');self.run_start();ids=[i for i,p in self.events];self.assertNotIn(0x0603,ids);self.assertNotIn(0x0613,ids);self.assertNotIn('DATA',ids);self.assertEqual(self.owner.apn['value'],'')
 def test_bad_profiles_refuse_before_initial_radio(self):
  self.settings['network']['apn']='auto';self.settings['profiles']['invalid']='not a valid profile'
  with self.assertRaises(RuntimeError):self.run_start()
  self.assertEqual(self.events,[])
 def test_actual_exact_dt_tuple_and_bad_shapes(self):
  good=self.dt.read_bytes()
  bad=(b'google,komodo\0google,zumapro\0',b'google,zumapro\0',b'google,zumapro-caiman\0google,zumapro\0',b'google,zumapro-komodo\0google,zuma\0',b'google,zumapro\0google,zumapro-komodo\0',b'google,zumapro-komodo\0google,zumapro',b'google,zumapro-komodo\0google,zumapro\0extra\0',b'x'*4097,b'')
  with patch.object(radio_power,'COMPATIBLE',self.dt):
   self.assertEqual(radio_power.profile(self.settings),radio_power.KOMODO)
   for raw in bad:
    self.dt.write_bytes(raw)
    with self.subTest(shape=len(raw)),self.assertRaises(ValueError):radio_power.profile(self.settings)
   self.dt.write_bytes(good)
 def test_default_does_not_read_dt(self):
  self.settings['network']['startup_profile']='default'
  with patch.object(Path,'open',side_effect=AssertionError('default attempted DT read')):self.assertEqual(radio_power.profile(self.settings),'default')
if __name__=='__main__':unittest.main()
