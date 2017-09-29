# Ann Arbor Tees Autodeploy

Our custom CI infrastructure for Rails apps using Capistrano.



## Testing (verifying the CI works)

The `Dockerfile` and `docker-compose` are used to provide a test environment
with a fake git repository that can be fast-forwarded.

#### Run all verifications:

```bash
sudo ./verify.sh
```

It takes some time -- especially on the first run, since it has to build the containers.

#### Open interactive test environment:

```bash
sudo ./test_environment/begin.sh
```

or with a specific scenario's environment:

```bash
sudo ./test_environment/begin.sh specs_fail
```

### How

The `bundle` binary is stubbed in these test environments. Check out
`test_environment/bundle_stub.rb` and `test_environment/mock_bundle*.rb`.




## Using (automated testing/deployment for apps)

First, you need to have a file in your home directory called `autodeploy.json`.
This describes the MYSQL database in which spec and deployment results will be dumped.

```json
{
  "host":     "172.45.46.47",
  "username": "root",
  "password": "good-password",
  "database": "autodeploy"
}
```

(Note that the database must already exist)

### Running in-place
```bash
./ci.bash /path/to/project-root/
```

### Running detached
```bash
./ci-detached.bash /path/to/project-root/
```

## VPN notes

Not directly related to this system, but ...

``` bash
sudo apt-get install network-manager-openvpn network-manager-openvpn-gnome networkmanager-pptp network-manager-vpnc
```

Then network manager should be able to import .ovpn files.
