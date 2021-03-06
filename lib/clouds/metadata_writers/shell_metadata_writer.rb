 #
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats



module RightScale

  module MetadataWriters

    # Shell script writer.
    class ShellMetadataWriter < MetadataWriter


      # Initializer.
      #
      # === Parameters
      # options[:file_extension](String):: dotted extension for shell files or nil
      def initialize(options)
        # defaults
        options = options.dup
        default_file_extension = RightScale::Platform.windows? ? '.bat' : '.sh'
        options[:file_extension] ||= default_file_extension
        @formatter = FlatMetadataFormatter.new(options)

        # super
        super(options)
      end

      protected

      if RightScale::Platform.windows?

        WINDOWS_SHELL_HEADER = ['@echo off',
                                'rem # Warning: this file has been auto-generated',
                                'rem # any modifications can be overwritten']

        # Write given metadata to a bash file.
        #
        # === Parameters
        # metadata(Hash):: Hash-like metadata to write
        #
        # === Return
        # always true
        def write_file(metadata)
          return unless @formatter.can_format?(metadata)
          flat_metadata = @formatter.format(metadata)

          env_file_path = create_full_path(@file_name_prefix)
          File.open(env_file_path, "w", DEFAULT_FILE_MODE) do |f|
            f.puts(WINDOWS_SHELL_HEADER)
            flat_metadata.each do |k, v|
              # ensure value is a single line (multiple lines could be interpreted
              # as subsequent commands) by truncation since windows shell doesn't
              # have escape characters.
              v = self.class.first_line_of(v)
              f.puts "set #{k}=#{v}"
            end
          end
          true
        end

      else  # not windows

        LINUX_SHELL_HEADER = ['#!/bin/bash',
                              '# Warning: this file has been auto-generated',
                              '# any modifications can be overwritten']

        # Write given metadata to a bash file.
        #
        # === Parameters
        # metadata(Hash):: Hash-like metadata to write
        #
        # === Return
        # always true
        def write_file( metadata)
          return unless @formatter.can_format?(metadata)
          flat_metadata = @formatter.format(metadata)

          env_file_path = create_full_path(@file_name_prefix)
          File.open(env_file_path, "w", DEFAULT_FILE_MODE) do |f|
            f.puts(LINUX_SHELL_HEADER)
            flat_metadata.each do |k, v|
              # escape backslashes and double quotes.
              v = self.class.escape_double_quotes(v)
              f.puts "export #{k}=\"#{v}\""
            end
          end
          true
        end

      end  # if windows

    end  # ShellMetadataWriter

  end  # MetadataWriters

end  # RightScale
