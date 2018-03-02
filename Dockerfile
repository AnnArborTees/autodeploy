# This is used for testing and is not required for production

FROM ruby:2.4.1

ARG mockbundle=mock_bundle.rb

# Debian packages
RUN apt-get update
RUN apt-get install -y mysql-client vim tmux

# Ruby gems
RUN gem install byebug --no-ri --no-rdoc
RUN gem install bundler --no-ri --no-rdoc

# Home directory
RUN mkdir -p /home
WORKDIR /home
ENV HOME /home
COPY ./test_environment/tmux.conf /home/.tmux.conf
RUN mkdir -p /home/ssh
COPY ./ssh/* /home/ssh/

# Test app and mock bundle
RUN mkdir -p /gitstuff/test_app_remote
RUN mkdir -p /home/test_app
COPY ./test_environment/$mockbundle /mock_bundle.rb
# Overwrite the real bundle with our mock one (powered by bundle_stub.rb)
COPY ./test_environment/bundle_stub.rb /bundle_stub.rb
COPY ./test_environment/test_app/* /home/test_app
COPY ./test_environment/git-start.tar.gz /gitstuff/git-start.tar.gz
COPY ./test_environment/git-updated.tar.gz /gitstuff/git-updated.tar.gz
# Set up fake (local) git remote
RUN cd /home/test_app            && tar -xf /gitstuff/git-start.tar.gz
RUN cd /gitstuff/test_app_remote && tar -xf /gitstuff/git-updated.tar.gz
RUN cd /home/test_app            && git remote add origin /gitstuff/test_app_remote/.git
RUN cd /home/test_app            && git fetch && git reset --hard
RUN cd /home/test_app            && git branch --set-upstream-to=origin/master master
ENV DELAY_BETWEEN_PULLS 1

# Database config
COPY ./test_environment/autodeploy.json /home/autodeploy.json

#RUN cd /home/autodeploy && bundle install

CMD ./ci.bash test_app --once && bundle verify "$(./show_last_run.bash)"
