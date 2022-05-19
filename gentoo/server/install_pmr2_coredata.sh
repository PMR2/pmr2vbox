#!/bin/bash -i
# XXX this script assumes vboxtools has been used to "activate" a
# VirtualBox control environment.

if [ ! -f /var/lib/virtuoso/db/.pmr2_schema ]; then
    # TODO figure out a better location than this?
    DB=/var/lib/virtuoso/db
    SCHEMA_HOME=$(realpath ${DB})
    INI=/var/lib/virtuoso/db/virtuoso.ini

    # ensure that the realpath to the SCHEMA_HOME is usable
    if [ ! "${SCHEMA_HOME}" == "${DB}" ]; then
        if ! grep '^DirsAllowed.*=' "${INI}" | grep -q "${SCHEMA_HOME}" ; then
            ORIG=$(grep '^DirsAllowed.*= \.' "${INI}")
            sed -i "s#${ORIG}#${ORIG}, ${SCHEMA_HOME}#" "${INI}"
        fi
    fi

    # restart virtuoso and import schema
    echo "restarting virtuoso with any configuration changes"
    /etc/init.d/virtuoso restart
    sleep 3

    SCHEMA_FILES="
    celltype.owl
    chebi.owl
    fma.owl
    go.owl
    OPBv1.04.owl
    rdf-schema.rdf
    sbmlrdfschema.rdf
    "

    for file in ${SCHEMA_FILES}; do
        if [ ! -f "${SCHEMA_HOME}/${file}" ]; then
            wget -c ${DIST_SERVER}/schema/${file} -O "${SCHEMA_HOME}/${file}"
        fi
    done

    isql-v <<- EOF
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/fma.owl'), '', 'http://namespaces.physiomeproject.org/fma.owl');
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/go.owl'), '', 'http://namespaces.physiomeproject.org/go.owl');
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/celltype.owl'), '', 'http://namespaces.physiomeproject.org/celltype.owl');
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/chebi.owl'), '', 'http://namespaces.physiomeproject.org/chebi.owl');
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/OPBv1.04.owl'), '', 'http://namespaces.physiomeproject.org/opb.owl');

	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/rdf-schema.rdf'), '', 'http://namespaces.physiomeproject.org/ricordo-schema.rdf') ;
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/sbmlrdfschema.rdf'), '', 'http://namespaces.physiomeproject.org/ricordo-sbml-schema.rdf');

	rdfs_rule_set('ricordo_rule', 'http://namespaces.physiomeproject.org/ricordo-schema.rdf');
	rdfs_rule_set('ricordo_rule', 'http://namespaces.physiomeproject.org/ricordo-sbml-schema.rdf');
	EOF

    touch "${DB}/.pmr2_schema"
else
    echo "virtuoso assumed to have been created and schema imported; skipping"
fi
