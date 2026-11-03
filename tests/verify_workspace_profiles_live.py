import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import time
import uuid
spec=importlib.util.spec_from_file_location('wp', str(Path(__file__).resolve().parents[1] / 'assets/workspace_profiles.py'))
p=importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
h=p.Hypr(lua=True)
before=h.query('clients'); focused=[m['activeWorkspace']['name'] for m in h.query('monitors') if m.get('focused')]
suffix = uuid.uuid4().hex[:8]
cls='caelestia-profile-verification-' + suffix
fallback=next(m['name'] for m in h.query('monitors') if not m['name'].startswith('AI-'))
a=dict(program='/bin/sh',arguments=['-c', f'sleep 2; exec foot --app-id={cls} --title=Profile-verification sleep 300'],workspace='profile-verification-a-' + suffix,monitor='DISCONNECTED-TEST',resource='',matchClass=cls,matchTitle='',alwaysNew=False)
missing=dict(a,program='caelestia-intentionally-missing-test',arguments=[],matchClass='absent')
try:
    warnings=p.activate(dict(name='Verification',apps=[missing,a]),h,timeout=12)
    clients=h.query('clients'); test=[c for c in clients if c['class']==cls]
    assert len(test)==1, test
    address=test[0]['address']
    assert test[0]['workspace']['name']=='profile-verification-a-' + suffix, test
    assert test[0]['monitor']==next(m['id'] for m in h.query('monitors') if m['name']==fallback)
    a['workspace']='profile-verification-b-' + suffix; a['monitor']=fallback
    assert not p.activate(dict(name='Reuse',apps=[a]),h,timeout=12)
    reused=[c for c in h.query('clients') if c['class']==cls]
    assert len(reused)==1 and reused[0]['address']==address and reused[0]['workspace']['name']=='profile-verification-b-' + suffix
    assert all(next((n for n in h.query('clients') if n['address']==c['address']), c)['workspace']==c['workspace'] for c in before)
    assert [m['activeWorkspace']['name'] for m in h.query('monitors') if m.get('focused')]==focused
    with tempfile.TemporaryDirectory() as tmp:
        p.STATE=Path(tmp)/'profiles.json'
        doc=p.load(); doc['profiles'].append(p.validate(dict(name='Saved test',apps=[a])))
        p.save(doc); assert p.load()==doc
    print('PASS: real delayed launch, monitor fallback, missing app continuation, unique reuse/address preserved, workspace placement, focus preserved, unrelated windows untouched, persistence')
finally:
    for c in h.query('clients'):
        if c['class']==cls:
            h.ctl('dispatch','hl.dsp.window.close({ window = %s })' % json.dumps('address:'+c['address']))
