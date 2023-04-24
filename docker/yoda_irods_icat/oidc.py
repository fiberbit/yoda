#!/usr/bin/env python

import requests


USERINFO_URI = "https://oauth.mocklab.io/userinfo"
EMAIL_FIELD = "email"


def unescape_irods_pam_password(password):
    return password.replace('\@', '@')


def validate_token(username, token, sub):
    # Send token validation request.
    headers = {"Authorization": "Bearer {}".format(token)}
    r = requests.get(USERINFO_URI, headers=headers)

    # Check http status.
    if r.status_code != 200:
        print('Failed to get a successful userinfo response '
              '\n{}\n{}'
              .format(r.status_code, r.text.encode(r.encoding)))
        return False

    # Retrieve token email.
    try:
        email = r.json()[EMAIL_FIELD]
        if not isinstance(email, list):
            email = [email]
        email = [x.lower() for x in email]
        userinfo_sub = r.json()['sub']
    except Exception:
        print('Unable to extract data from the userinfo  '
              'response.\nKey: {}\nUserinfo:\n{}'
              .format(EMAIL_FIELD, r.text))
        return False

    # Check if token email corresponds with username.
    if username in email and sub == userinfo_sub:
        return True

    return False


def pam_sm_authenticate(pamh, flags, argv):
    # Get the username.
    try:
        username = pamh.get_user()
    except Exception:
        print('User unknown')
        return pamh.PAM_USER_UNKNOWN

    # Get the token.
    token = pamh.authtok
    if token is None:
        print('Missing token')
        return pamh.PAM_AUTH_ERR

    token = unescape_irods_pam_password(token)

    # Remove the prefix from the portal.
    if token[0:14] == '++oidc_token++':
         token = token[14:]
         try:
             sub_ix = token.index('end_sub')
             sub = token[0:sub_ix]
             token = token[sub_ix + 7:]
         except:
             sub = ''
    else:
        print('Not an oidc token')
        return pamh.PAM_PERM_DENIED

    # Validate the token.
    if(validate_token(username, token, sub)):
        return pamh.PAM_SUCCESS

    print('Validation failed')
    return pamh.PAM_AUTH_ERR
