#!/usr/local/bin/python3

#   Mac usage: ./extract_tampermonkey_script.py "/Users/<USER>/Library/Application Support/Google/Chrome/Default/Local Extension Settings/<EXTENSION_ID>/" "<INSTALL_LOCATION>"
#        i.e.: ./extract_tampermonkey_script.py "/Users/foo/Library/Application Support/Google/Chrome/Default/Local Extension Settings/dhdgffkkebhmkfjojejmpbldmpobfkfo/" "$HOME/Git/tampermonkey-scripts"

import leveldb
import sys
import re
import json
import codecs
import base64

extensionSettingsPath = " ".join(sys.argv[1:-1])
script_path = sys.argv[-1]
db = leveldb.LevelDB(extensionSettingsPath)

def main():
    create_backup_file()
    backup_script_files()

def create_backup_file():
    write_file('tampermonkey-backup.txt', get_backup_json())

def get_backup_json():
    meta_pattern = re.compile("^@meta(.*)$")

    backup = {
        "created_by": "Tampermonkey",
        "scripts": [],
        "settings": {},
        "version": "1"
    }

    for bk, bv in db.RangeIter():
        k = bk.decode('utf-8')
        v = bv.decode('utf-8')
        if k == '#config':
            backup["settings"] = json.loads(v)['value']
        elif meta_pattern.match(k):
            meta = json.loads(v)['value']
            uuid = meta['uuid']
            backup['scripts'].append({
                "enabled": meta['enabled'],
                "name": meta['name'],
                "options": meta['options'],
                "position": meta['position'],
                "requires": [],
                "source": get_b64_source(uuid),
                "storage": get_storage_object(uuid),
                "uuid": uuid
            })
    return json.dumps(backup)

def get_b64_source(uuid):
    source_data = get_db_value(f"@source#{uuid}")
    source = json.loads(source_data)['value']
    return base64.b64encode(bytes(source, 'ascii')).decode('ascii')

def get_db_value(key):
    b_value = db.Get(bytes(key, "ascii"))
    return b_value.decode('utf-8')

def get_storage_object(uuid):
    storage_data = get_db_value(f"@st#{uuid}")
    storage_object = json.loads(storage_data)['value']
    storage_object['data'] = {}
    return storage_object

def write_file(name, content):
    full_name = f"{script_path}/{name}.js"
    print(f"Writing to {full_name}")

    with codecs.open(full_name, 'w', 'utf-8') as text_file:
        text_file.write(content)

def backup_script_files():
    pattern = re.compile("^@source(.*)$")
    for bk, bv in db.RangeIter():
        k = bk.decode('utf-8')
        v = bv.decode('utf-8')
        m = pattern.match(k)
        if m:
            content = json.loads(v)['value']
            name = re.search("@name\s+([\w -\(\)]+)\n", content).groups()[0]
            write_file(name, content)

main()