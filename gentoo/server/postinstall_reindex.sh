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

echo -n "attempting to change default dba password for virtuoso... "
su ${ZOPE_USER} -c "bin/instance-deploy debug" << EOF | grep OKAY > /dev/null
from subprocess import Popen, PIPE
from zope.component import getUtility
from zope.component.hooks import setSite
from pmr2.app.settings.interfaces import IPMR2GlobalSettings
from pmr2.virtuoso.interfaces import ISettings

setSite(app.pmr)
pmr2_settings = getUtility(IPMR2GlobalSettings)
virtuoso_settings = ISettings(pmr2_settings)

# XXX assuming user is dba
# TODO create user if user is not 'dba'
cmd = 'set password dba %s;\\ncheckpoint;\\n' % virtuoso_settings.password
p = Popen(['${ISQL_V}'], stdin=PIPE, stdout=PIPE)
out, err = p.communicate(cmd.encode('utf8'))

# string based workaround because sys.exit does not work within debug shell
if 'Done' in out:
    print('OKAY')

# to ensure the above if statement also get executed because zopepy can
# be buggy with trailing if/indented statements?
print('')

EOF
echo "done"

# TODO reindex exposure files
# TODO optional rebuild of all exposures, though this need is diminished
# if/when dynamically generated views are done
su ${ZOPE_USER} -c "bin/instance-deploy debug" << EOF
import zope.component
from zope.component.hooks import setSite
from zope.annotation import IAnnotations
from pmr2.virtuoso.interfaces import IWorkspaceRDFIndexer
from morre.pmr2.interfaces import IMorreServer
import transaction

setSite(app.pmr)
catalog = app.pmr.portal_catalog
virtuoso_workspace_count = morre_exposure_file_count = 0

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
print("%d workspaces exported RDF to Virtuoso" % virtuoso_workspace_count)
print("%d exposure file reindexed by Morre" % morre_exposure_file_count)
EOF
