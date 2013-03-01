require 'capistrano/recipes/deploy/strategy/copy'
require 'erb'
require 'yaml'
require 'aws/s3'

module Capistrano
  module Deploy
    module Strategy
      class S3Copy < Copy

        def initialize(config={})
          super

          @bucket_name = configuration[:aws_releases_bucket]
          raise Capistrano::Error, "Missing configuration[:aws_releases_bucket]" if @bucket_name.nil?

          @bucket_prefix = configuration[:aws_releases_prefix]
          raise Capistrano::Error, "Missing configuration[:aws_releases_bucket_prefix]" if @bucket_prefix.nil?

          aws_config = YAML::load(ERB.new(IO.read("config/aws.yml")).result)[rails_env]

          AWS.config(@aws_config)

          @bucket = AWS::S3.buckets.create(@bucket_name)

        end

        attr_reader :bucket_name, :bucket_prefix

        def check!
          super.check do |d|
            d.remote.command("s3cmd")
          end
        end

        # Distributes the file to the remote servers
        def distribute!
          package_path = filename
          package_name = File.basename(package_path)

          if configuration.dry_run
            logger.debug s3_push_cmd
          else
            system(s3_push_cmd)
            raise Capistrano::Error, "shell command failed with return code #{$?}" if $? != 0
          end

          # run "s3cmd get s3://#{bucket_name}/#{rails_env}/#{package_name} #{remote_filename} 2>&1"
          run "s3cmd get s3://#{File.join [bucket_name, bucket_prefix, rails_env, package_name].compact} #{remote_filename} 2>&1"
          run "cd #{configuration[:releases_path]} && #{decompress(remote_filename).join(" ")} && rm #{remote_filename}"
          logger.debug "done!"

          build_aws_install_script
        end

        def binding
          super
        end

      end
    end
  end
end
