# Ann Arbor Tees Autodeploy

Our custom CI infrastructure for Rails apps using Capistrano.



## Testing (verifying the CI works)

The `Dockerfile` and `docker-compose` are used to provide a test environment
with a fake git repository that can be fast-forwarded.

#### Run all verifications:

```bash
sudo ./verify.sh
```

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

In the app root, run `/path/to/autodeploy/ci.bash`.
