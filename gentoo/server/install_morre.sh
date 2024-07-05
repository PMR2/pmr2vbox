#!/bin/bash
set -e

# JDK 11 or greater not supported by neo4j
emerge --noreplace dev-java/openjdk-bin:8

MORRE_DEP_JARS="
activation-1.1.jar
aopalliance-1.0.jar
apache-jena-libs-3.0.0.pom
axis-1.4.jar
axis-jaxrpc-1.4.jar
axis-saaj-1.4.jar
axis-wsdl4j-1.5.1.jar
BFLog-1.3.3.jar
BFUtils-0.4.1.jar
biojava3-ontology-3.1.0.jar
BiVeS-CellML-1.6.2.jar
BiVeS-Core-1.6.8.jar
commons-cli-1.3.jar
commons-codec-1.9.jar
commons-csv-1.0.jar
commons-discovery-0.2.jar
commons-lang3-3.1.jar
commons-logging-1.1.3.jar
dom4j-1.6.1.jar
gson-2.2.2.jar
guava-18.0.jar
guice-4.0-beta.jar
guice-multibindings-4.0-beta.jar
httpclient-4.5.2.jar
httpclient-cache-4.2.5.jar
httpcore-4.4.4.jar
jackson-annotations-2.3.0.jar
jackson-core-2.2.1.jar
jackson-databind-2.3.3.jar
JavaEWAH-0.8.6.jar
javax.inject-1.jar
jaxen-1.1.1.jar
jcl-over-slf4j-1.7.21.jar
jCOMODI-0.5.9.jar
jdom-1.0.jar
jdom-1.1.3.jar
jdom2-2.0.5.jar
jdom-contrib-1.1.3.jar
jena-arq-3.0.0.jar
jena-base-3.0.0.jar
jena-core-3.0.0.jar
jena-iri-3.0.0.jar
jena-shaded-guava-3.0.0.jar
jena-tdb-3.0.0.jar
jfact-4.0.0.jar
jigsaw-2.2.6.jar
jlibsedml-2.0.0.jar
jmathml-2.1.0.jar
joda-time-2.3.jar
jsbml-1.1-b1.jar
jsbml-arrays-1.1-b1.jar
jsbml-comp-1.1-b1.jar
jsbml-core-1.1-b1.jar
jsbml-distrib-1.1-b1.jar
jsbml-dyn-1.1-b1.jar
jsbml-fbc-1.1-b1.jar
jsbml-groups-1.1-b1.jar
jsbml-layout-1.1-b1.jar
jsbml-multi-1.1-b1.jar
jsbml-qual-1.1-b1.jar
jsbml-render-1.1-b1.jar
jsbml-req-1.1-b1.jar
jsbml-spatial-1.1-b1.jar
jsbml-tidy-1.1-b1.jar
jsonld-java-0.5.0.jar
jsonld-java-sesame-0.5.0.jar
json-simple-1.1.1.jar
jsoup-1.7.2.jar
jsr305-2.0.1.jar
jtidy-r938.jar
junit-4.5.jar
libthrift-0.9.2.jar
log4j-1.2.17.jar
lucene-backward-codecs-5.5.0.jar
mail-1.4.jar
masymos-core-0.9.0.jar
miriam-lib-1.1.6.jar
org.apache.commons.io-2.4.jar
owlapi-api-4.0.2.jar
owlapi-distribution-4.0.2.jar
saxon-8.7.jar
Saxon-B-9.0.jar
saxon-dom-8.7.jar
sbgn-SEMS-2.jar
semargl-core-0.6.1.jar
semargl-rdf-0.6.1.jar
semargl-rdfa-0.6.1.jar
semargl-sesame-0.6.1.jar
sesame-model-2.7.12.jar
sesame-rio-api-2.7.12.jar
sesame-rio-binary-2.7.12.jar
sesame-rio-datatypes-2.7.12.jar
sesame-rio-languages-2.7.12.jar
sesame-rio-n3-2.7.12.jar
sesame-rio-nquads-2.7.12.jar
sesame-rio-ntriples-2.7.12.jar
sesame-rio-rdfjson-2.7.12.jar
sesame-rio-rdfxml-2.7.12.jar
sesame-rio-trig-2.7.12.jar
sesame-rio-trix-2.7.12.jar
sesame-rio-turtle-2.7.12.jar
sesame-util-2.7.12.jar
slf4j-log4j12-1.7.21.jar
slf4j-api-1.7.21.jar
spi-0.2.4.jar
stax2-api-3.1.4.jar
staxmate-2.3.0.jar
trove4j-3.0.3.jar
woodstox-core-5.0.1.jar
xalan-2.7.0.jar
xercesImpl-2.8.0.jar
xml-apis-1.3.03.jar
xmlutils-0.6.6.jar
xom-1.2.5.jar
xpp3_min-1.1.4c.jar
xstream-1.3.1.jar
xz-1.5.jar
"

MORRE_JARS="
masymos-morre-pmr2-0.9.0.jar
"

mkdir -p "${MORRE_HOME}"
chown ${MORRE_USER}:${MORRE_USER} "${MORRE_HOME}"
cd "${MORRE_HOME}"

if [ ! -d $NEO4J_VERSION ]; then
    su ${MORRE_USER} -c "wget $DIST_SERVER/$NEO4J_VERSION.tar.gz"
    su ${MORRE_USER} -c "tar xf ${NEO4J_VERSION}.tar.gz"
fi 

cd $NEO4J_VERSION
su ${MORRE_USER} -c "mkdir -p lib/ext plugins"

for jar in ${MORRE_DEP_JARS}; do
    if [ ! -f "lib/ext/${jar}" ]; then
        su ${MORRE_USER} -c "wget \"${JARS_SERVER}/${jar}\" -O \"lib/ext/${jar}\""
    fi
done

for jar in ${MORRE_JARS}; do
    if [ ! -f "plugins/${jar}" ]; then
        su ${MORRE_USER} -c "wget \"${JARS_SERVER}/${jar}\" -O \"plugins/${jar}\""
    fi
done

if ! grep MaSyMoS conf/neo4j.conf > /dev/null ; then
    su ${MORRE_USER} -c "patch -p0" <<- EOF
	--- bin/neo4j-shared.sh 2017-01-04 15:42:46.152837739 +1300
	+++ bin/neo4j-shared.sh 2017-01-04 15:25:36.948192325 +1300
	@@ -39,7 +39,7 @@
	 }
	 
	 build_classpath() {
	-  CLASSPATH="\${NEO4J_PLUGINS}:\${NEO4J_CONF}:\${NEO4J_LIB}/*:\${NEO4J_PLUGINS}/*"
	+  CLASSPATH="\${NEO4J_PLUGINS}:\${NEO4J_CONF}:\${NEO4J_LIB}/*:\${NEO4J_PLUGINS}/*:\${NEO4J_LIB}/ext/*"
	 }
	 
	 detect_os() {
	--- conf/neo4j.conf 2016-05-06 11:44:36.000000000 +1200
	+++ conf/neo4j.conf 2016-06-10 11:10:20.022417151 +1200
	@@ -4,6 +4,7 @@
	 
	 # The name of the database to mount
	 #dbms.active_database=graph.db
	+dbms.active_database=MaSyMoS
	 
	 # Paths of directories in the installation.
	 #dbms.directories.data=data
	@@ -17,7 +18,7 @@
	 
	 # Whether requests to Neo4j are authenticated.
	 # To disable authentication, uncomment this line
	-#dbms.security.auth_enabled=false
	+dbms.security.auth_enabled=false
	 
	 # Enable this to be able to upgrade a store from an older version.
	 #dbms.allow_format_migration=true
	@@ -119,3 +223,4 @@
	 # neo4j-server-examples under /examples/unmanaged, resulting in a final URL of
	 # http://localhost:7474/examples/unmanaged/helloworld/{nodeId}
	 #dbms.unmanaged_extension_classes=org.neo4j.examples.server.unmanaged=/examples/unmanaged
	+dbms.unmanaged_extension_classes=de.unirostock.morre.server.plugin=/morre
	EOF
fi

cat << EOF > /etc/init.d/morre.pmr2
#!/sbin/openrc-run
# Distributed under the terms of the GNU General Public License v2

NEO4J_HOME=${MORRE_HOME}/${NEO4J_VERSION}
DAEMONUSER=${MORRE_USER}
DAEMONGROUP=${MORRE_USER}

SCRIPT=\${NEO4J_HOME}/bin/neo4j
PIDFILE=\${NEO4J_HOME}/run/neo4j.pid

[ -f \$SCRIPT ] || eend 1

DAEMON=\$SCRIPT

# assume this JVM is installed.
export JAVA_HOME=/usr/lib/jvm/openjdk-bin-8

depend() {
    need net
}

start() {
    ebegin "Starting \${SVCNAME}"
    start-stop-daemon --quiet --oknodo \\
                      --chuid \$DAEMONUSER:\$DAEMONGROUP \\
                      --pidfile \${PIDFILE} \\
                      --exec \${DAEMON} --start -- start
    retval=\$?
    eend \${retval}
}

stop() {
    ebegin "Stopping \${SVCNAME}"
    start-stop-daemon --quiet --oknodo \\
                      --chuid \$DAEMONUSER:\$DAEMONGROUP \\
                      --pidfile \${PIDFILE} \\
                      --exec \${DAEMON} --stop -- stop
    retval=\$?
    eend \${retval}
}

restart() {
    ebegin "Restarting \${SVCNAME}"
    start-stop-daemon --quiet --oknodo \\
                      --chuid \$DAEMONUSER:\$DAEMONGROUP \\
                      --pidfile \${PIDFILE} \\
                      --exec \${DAEMON} --restart -- restart
    retval=\$?
    eend \${retval}
}
EOF

chmod +x /etc/init.d/morre.pmr2
