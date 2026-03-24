The mail configuration needs a `.authinfo.gpg` file containing

```
machine imap.domain.tld login [USER] password [PASS] port 993
machine stmp.domain.tld login [USER] password [PASS] port 587
```

for each mail address.
