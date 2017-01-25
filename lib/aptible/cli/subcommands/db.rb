require 'term/ansicolor'
require 'uri'

module Aptible
  module CLI
    module Subcommands
      module DB
        def self.included(thor)
          thor.class_eval do
            include Helpers::Operation
            include Helpers::Database
            include Helpers::Token
            include Term::ANSIColor

            desc 'db:list', 'List all databases'
            option :environment
            define_method 'db:list' do
              scoped_environments(options).each do |env|
                present_environment_databases(env)
              end
            end

            desc 'db:create HANDLE', 'Create a new database'
            option :type, default: 'postgresql'
            option :size, default: 10, type: :numeric
            option :environment
            define_method 'db:create' do |handle|
              environment = ensure_environment(options)
              database = environment.create_database(handle: handle,
                                                     type: options[:type])

              if database.errors.any?
                raise Thor::Error, database.errors.full_messages.first
              else
                op = database.create_operation!(type: 'provision',
                                                disk_size: options[:size])
                attach_to_operation_logs(op)
                say database.reload.connection_url
              end
            end

            desc 'db:clone SOURCE DEST', 'Clone a database to create a new one'
            option :environment
            define_method 'db:clone' do |source_handle, dest_handle|
              source = ensure_database(options.merge(db: source_handle))
              dest = clone_database(source, dest_handle)
              say dest.connection_url
            end

            desc 'db:dump HANDLE', 'Dump a remote database to file'
            option :environment
            define_method 'db:dump' do |handle|
              database = ensure_database(options.merge(db: handle))
              with_postgres_tunnel(database) do |url|
                filename = "#{handle}.dump"
                say "Dumping to #{filename}"
                `pg_dump #{url} > #{filename}`
              end
            end

            desc 'db:execute HANDLE SQL_FILE', 'Executes sql against a database'
            option :environment
            define_method 'db:execute' do |handle, sql_path|
              database = ensure_database(options.merge(db: handle))
              with_postgres_tunnel(database) do |url|
                say "Executing #{sql_path} against #{handle}"
                `psql #{url} < #{sql_path}`
              end
            end

            desc 'db:tunnel HANDLE', 'Create a local tunnel to a database'
            option :environment
            option :port, type: :numeric
            option :type, type: :string
            define_method 'db:tunnel' do |handle|
              desired_port = Integer(options[:port] || 0)
              database = ensure_database(options.merge(db: handle))

              credential = find_tunnel_credential(database, options[:type])

              say "Creating #{credential.type} tunnel to #{database.handle}...",
                  :green

              if options[:type].nil?
                types = database.database_credentials.map(&:type).join(', ')
                say 'Use --type TYPE to specify a tunnel type', :green
                say "Valid types for #{database.handle}: #{types}", :green
              end

              with_local_tunnel(credential, desired_port) do |tunnel_helper|
                port = tunnel_helper.port
                say "Connect at #{local_url(credential, port)}", :green

                uri = URI(local_url(credential, port))
                db = uri.path.gsub(%r{^/}, '')
                say 'Or, use the following arguments:', :green
                say("* Host: #{uri.host}", :green)
                say("* Port: #{uri.port}", :green)
                say("* Username: #{uri.user}", :green) unless uri.user.empty?
                say("* Password: #{uri.password}", :green)
                say("* Database: #{db}", :green) unless db.empty?

                say 'Connected. Ctrl-C to close connection.'

                begin
                  tunnel_helper.wait
                rescue Interrupt
                  say 'Closing tunnel'
                end
              end
            end

            desc 'db:deprovision HANDLE', 'Deprovision a database'
            option :environment
            define_method 'db:deprovision' do |handle|
              database = ensure_database(options.merge(db: handle))
              say "Deprovisioning #{database.handle}..."
              database.create_operation!(type: 'deprovision')
            end

            desc 'db:backup HANDLE', 'Backup a database'
            option :environment
            define_method 'db:backup' do |handle|
              database = ensure_database(options.merge(db: handle))
              say "Backing up #{database.handle}..."
              op = database.create_operation!(type: 'backup')
              attach_to_operation_logs(op)
            end
          end
        end
      end
    end
  end
end
