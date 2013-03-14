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

          @bucket_name = configuration[:releases_bucket]
          raise Capistrano::Error, "Missing configuration[:releases_bucket]" if @bucket_name.nil?

          @bucket_prefix = configuration[:releases_bucket_prefix]

          aws_config = YAML::load(ERB.new(IO.read("config/aws.yml")).result)[rails_env]
          aws_config.delete "bucket"
          aws_config = Hash[ aws_config.map{|k,v| [k.to_s,v] } ]

          AWS.config(aws_config)

          @bucket = AWS::S3.new.buckets.create(@bucket_name)

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
          s3_options = { :acl => :private, :server_side_encryption => :aes256 }
          s3_path = File.join [ bucket_prefix, package_name ].compact
          marker = File.join [ bucket_prefix, "latest.tar.gz" ].compact

          if configuration.dry_run
            logger.debug "Would upload to s3://#{@bucket_name}/#{s3_path}"
          else
            logger.info "Uploading to s3://#{@bucket_name}/#{s3_path}"
            @bucket.objects[s3_path].write(File.open(filename), s3_options)
            @bucket.objects[marker].copy_from(s3_path, s3_options.merge(:metadata => {:original => s3_path}))
          end

          run "s3cmd get s3://#{bucket_name}/#{s3_path} #{remote_filename} 2>&1"
          run "cd #{configuration[:releases_path]} && #{decompress(remote_filename).join(" ")} && rm #{remote_filename}"
        end

        def build directory
          execute "running build script on #{directory}" do
            with_env "RAILS_ENV", configuration[:rails_env] do
              Dir.chdir(directory) { system(build_script) }
            end
          end if build_script
        end

        def binding
          super
        end

      end
    end
  end
end
