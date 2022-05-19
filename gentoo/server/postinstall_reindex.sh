#/bin/bash
set -e

cd "${PMR_HOME}"/pmr2.buildout

# start all required services
/etc/init.d/pmr2.instance start
/etc/init.d/morre.pmr2 start
/etc/init.d/virtuoso start

ISQL_V='isql-v'

timeout=10
echo "waiting ${timeout} seconds for services to finish starting..."
sleep ${timeout}

echo -n "attempting to configure access to virtuoso... "
su ${ZOPE_USER} -c "bin/instance-deploy debug" << EOF | grep OKAY > /dev/null
import sys
from subprocess import Popen, PIPE
from zope.component import getUtility
from zope.component.hooks import setSite
from pmr2.app.settings.interfaces import IPMR2GlobalSettings
from pmr2.virtuoso.interfaces import ISettings

def test_login(login, password):
    p = Popen(['${ISQL_V}', '-U', login, '-P', password],
        stdin=PIPE, stdout=PIPE, stderr=PIPE)
    out, err = p.communicate(u'STATUS();\\n')
    return p.returncode == 0

setSite(app.pmr)
pmr2_settings = getUtility(IPMR2GlobalSettings)
virtuoso_settings = ISettings(pmr2_settings)
login, password = virtuoso_settings.user, virtuoso_settings.password

def main():
    if test_login(login, password):
        return 0, (
            'pmr2 provided credentials valid',
        )
    elif login != 'dba':
        return 1, (
            'automatic configuration only supports the default "dba" user;',
            'either set "pmr2.virtuoso.interfaces.ISettings.user" to "dba"',
            'or reference the stored credentials and create the login in '
            'virtuoso',
        )
    if not test_login('dba', 'dba'):
        return 1, (
            'cannot login with default or configured credentials found '
            'in pmr2 settings;',
            'please either recreate the virtuoso database or correct the login '
            'credentials'
        )
    #
    cmd = u'set password dba %s;\\ncheckpoint;\\n' % password
    p = Popen(['${ISQL_V}'], stdin=PIPE, stdout=PIPE, stderr=PIPE)
    out, err = p.communicate(cmd.encode('utf8'))
    if len([o for o in out.split() if o == 'Done.']) == 2:
        return 0, (
            'modified password for "dba" to match pmr2 settings',
        )
    return 1, (
        'failed to configure password for virtuoso to match pmr2 settings',
    )

code, msg = main()
sys.stderr.write('\\n'.join(msg))
sys.stderr.write('\\n')
# can't do this inside this interpreter it does not work within debug shell
# sys.exit(code)
if code == 0:
    # use a string based workaround, see the grep above.
    print('OKAY')

# to ensure the above if statement also get executed because zopepy can
# be buggy with trailing if/indented statements?
print('')
EOF

su ${ZOPE_USER} -c "bin/instance-deploy debug" << EOF > /dev/null
import sys
import zope.component
from zope.component.hooks import setSite
from zope.annotation import IAnnotations
from pmr2.app.annotation.factory import has_note
from pmr2.app.annotation.interfaces import IExposureFileAnnotator
from pmr2.virtuoso.interfaces import IWorkspaceRDFIndexer
from morre.pmr2.interfaces import IMorreServer
import transaction

setSite(app.pmr)
catalog = app.pmr.portal_catalog
virtuoso_workspace_count = 0
virtuoso_exposure_file_count = 0
morre_exposure_file_count = 0

for b in catalog(portal_type='Workspace'):
    obj = b.getObject()
    annotations = IAnnotations(obj)
    if not 'pmr2.virtuoso.workspace.WorkspaceRDFInfo' in annotations:
        continue
    try:
        IWorkspaceRDFIndexer(obj)()
    except Exception as e:
        print('%s cannot be exported, exception: %s: %s' % (obj, type(e), e))
    else:
        virtuoso_workspace_count += 1

for b in catalog(portal_type='ExposureFile'):
    obj = b.getObject()
    if not has_note(obj, 'virtuoso_rdf'):
        continue
    _ = zope.component.getUtility(
        IExposureFileAnnotator, name='virtuoso_rdf')(obj, None).generate()
    virtuoso_exposure_file_count += 1

morre_server = zope.component.queryUtility(IMorreServer)
if morre_server and morre_server.index_on_wfstate:
    morre_server.path_to_njid.clear()
    for b in catalog(portal_type='ExposureFile',
                     pmr2_review_state={
                        'query': morre_server.index_on_wfstate}):
        path = b.getPath()
        if morre_server.add_model(path):
            morre_exposure_file_count += 1

transaction.commit()
sys.stderr.write('\n'.join([
    "%d workspaces exported RDF to Virtuoso" % virtuoso_workspace_count,
    "%d exposure file virtuoso_rdf reindexed" % virtuoso_exposure_file_count,
    "%d exposure file reindexed by Morre" % morre_exposure_file_count,
    ''
]))
EOF
