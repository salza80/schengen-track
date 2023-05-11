FROM ruby:2.7.8-bullseye

RUN gem install 'aws_lambda_ric'
ENTRYPOINT [ "/usr/local/bundle/bin/aws_lambda_ric" ]
CMD ["config/environment.Lamby.cmd"]