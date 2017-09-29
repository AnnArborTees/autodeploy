# Autodeploy SSH keys

Put any SSH private keys (.pem files) to this folder. They will be ignored by git.

`ci-detached.bash` will initialize the ssh-agent and add any keys found within this folder.
