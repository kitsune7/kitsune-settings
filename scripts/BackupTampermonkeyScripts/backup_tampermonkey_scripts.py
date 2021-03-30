#!/usr/local/bin/python3

#   Mac usage: ./extract_tampermonkey_script.py "/Users/<USER>/Library/Application Support/Google/Chrome/Default/Local Extension Settings/<EXTENSION_ID>/" "<INSTALL_LOCATION>"
#        i.e.: ./extract_tampermonkey_script.py "/Users/foo/Library/Application Support/Google/Chrome/Default/Local Extension Settings/dhdgffkkebhmkfjojejmpbldmpobfkfo/" "$HOME/Git/tampermonkey-scripts"

import leveldb
import sys
import re
import json
import codecs

extensionSettingsPath = " ".join(sys.argv[1:-1])
script_path = sys.argv[-1]

pattern = re.compile("^@source(.*)$")
db = leveldb.LevelDB(extensionSettingsPath)

for bk, bv in db.RangeIter():
    k = bk.decode('utf-8')
    v = bv.decode('utf-8')
    m = pattern.match(k)
    if m:
        content = json.loads(v)['value']
        print(content)
        name = re.search("@name\s+([\w -\(\)]+)\n", content).groups()[0]
        full_name = "%s/%s.js" % (script_path, name)

        print("Writing to %s" % full_name)

        with codecs.open(full_name, 'w', 'utf-8') as text_file:
            text_file.write(content)
