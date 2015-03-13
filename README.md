# designate-rr-monitor

An OpenStack Designate service monitor and round-robin DNS record manager. It allows you to check a series of servers, and update the round-robin record to include only those that are available.

You will need to do the usual `source ~/MYTENANT-openrc.sh` before using it, or ensure that `OS_AUTH_URL`, `OS_TENANT_NAME`, `OS_USERNAME` and `OS_PASSWORD` are in the environment.

```
Usage:
  designate-rr-monitor [OPTIONS] <record>

Options: 
  -d, --delete BOOLEAN   Delete all records
  -p, --port [NUMBER]    TCP port to check (Default is 80)
  -s, --servers STRING   whitespace-delimited list of servers (which may use 
                         brace expansion) 
  -w, --watch BOOLEAN    Monitor for changes after first check
  -k, --no-color         Omit color from output
      --debug            Show debug information
  -h, --help             Display help and usage details
```

For example, to do a one-off record update:
```shell
designate-rr-monitor -s "server-{01..04}.example.net" www.example.net
```

To do an update, then continue watching:
```shell
designate-rr-monitor -w -s "server-{01..04}.example.net" www.example.net
```

To delete all records:
```shell
designate-rr-monitor -d www.example.net
```
