#!/usr/bin/env python3.3

import json
import urllib.request
import urllib.parse

post_params = {'api': "add_ticket", 'key': "c5BT44108cYxBRHOYLnykazACsjkkQP3", 'product_id': "1", 'release_id': "1.0", 'title': "This is a test ticket", 'description': "Some description"}

data = urllib.parse.urlencode(post_params)
conn = urllib.request.urlopen("http://127.0.0.1/nodepoint/?" + data)
stream = conn.read()
result = json.loads(stream.decode(conn.info().get_param('charset', 'utf8')))
print(str(result))
