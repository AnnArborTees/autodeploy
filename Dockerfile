# This is used for testing and is not required for production

FROM ruby:2.2.7

# Apt dependencies
RUN apt-get update
RUN apt-get install -y mysql-client

# Ruby gem dependencies
RUN gem install json --no-ri --no-rdoc
RUN gem install mysql2 --no-ri --no-rdoc

# Home directory
RUN mkdir -p /home
WORKDIR /home
ENV HOME /home
RUN echo 'set -o vi' >> ~/.bashrc

# Test app and mock bundle
RUN mkdir -p /gitstuff/test_app_remote
RUN mkdir -p /home/test_app
COPY ./test_environment/mock_bundle.rb /mock_bundle.rb
RUN cp /mock_bundle.rb $(which bundle)
COPY ./test_environment/test_app/* /home/test_app
COPY ./test_environment/git-start.tar.gz /gitstuff/git-start.tar.gz
COPY ./test_environment/git-updated.tar.gz /gitstuff/git-updated.tar.gz
RUN cd /home/test_app            && tar -xf /gitstuff/git-start.tar.gz
RUN cd /gitstuff/test_app_remote && tar -xf /gitstuff/git-updated.tar.gz
RUN cd /home/test_app            && git remote add origin /gitstuff/test_app_remote/.git
RUN cd /home/test_app            && git fetch && git reset --hard
RUN cd /home/test_app            && git branch --set-upstream-to=origin/master master
ENV DELAY_BETWEEN_PULLS 1

# Database config
COPY ./test_environment/autodeploy.json /home/autodeploy.json

# Project files
COPY ./pull.bash /home/pull.bash
COPY ./db.rb /home/db.rb

ENTRYPOINT ["bash", "--login"]
