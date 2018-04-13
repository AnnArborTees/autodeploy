# Ann Arbor Tees Autodeploy

Our custom CI infrastructure.

Entrypoint is `lib/main.rb`.

Code that specifies which commands to run is in `lib/*_app.rb`.

Code for sending output to the database is in `lib/run.rb`.



## Testing (verifying the CI works)

The `Dockerfile` and `docker-compose` are used to provide a test environment
with a fake git repository that can be fast-forwarded.

To run the CI system once with a `TestApp`, execute

```bash
docker-compose run test
```

To inspect the last run created on the test database,

```bash
docker-compose run inspect
```

## Using (automated testing/deployment for apps)

On the AATCI Servers

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
ruby lib/main.rb /path/to/project-root/ type_of_app
```

### Running "detached"
This will run the CI script inside of a tmux session.
This lets us add ssh keys to the SSH agent for the deploy command.
(it also lets us inspect the running ci script whenever we want.)

```bash
./ci-detached.bash /path/to/project-root/ type_of_app
```

Where `type_of_app` is either `rails` or `test` (hard-coded before the loop in lib/main.rb)

### To start on bootup

Via ubuntu GUI, configure Startup Scripts to run. The startup script is just a script that has the configuration needed to run our apps, i.e. code to execute the "Runnnig detached" for CRM, then for Retail, then for Production etc.

TODO: Why does one CI server run on startup successfuly and the other doesn't?
