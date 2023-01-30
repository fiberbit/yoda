#!/usr/bin/env python
import requests
import os
import sys

r = requests.post('https://eus.yoda.test/api/user/auth-check',
                  headers={'X-Yoda-External-User-Secret': 'dummy_secret'},
                  auth=(os.getenv('PAM_USER'), sys.stdin.readline()),
                  verify=False)

if r.status_code == 200 and r.text == 'Authenticated':
    sys.exit(0)
else:
    sys.exit(1)
