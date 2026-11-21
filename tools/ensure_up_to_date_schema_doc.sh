#!/bin/bash

# tools/ensure_up_to_date_schema_doc.sh

docs/schema_doc_generator.sh

if git diff --quiet -- docs/docs/schema.html && [[ -z "$(git ls-files --others --exclude-standard docs/docs/schema.html)" ]]; then
    echo "Schema documentation is up to date."
    exit 0
else
    echo "Schema documentation is not up to date. Ensure schema doc is rebuilt."
    echo "Run 'docs/schema_doc_generator.sh' and commit the changes."
    exit 1
fi
