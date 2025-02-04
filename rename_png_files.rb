#!/usr/bin/env ruby

require 'find'

def rename_png_files(dir)
  Find.find(dir) do |path|
    if path =~ /\.PNG$/i  # Case-insensitive match for .PNG
      new_path = path.gsub(/\.PNG$/i, '.png')
      if path != new_path
        puts "Renaming: #{path} -> #{new_path}"
        File.rename(path, new_path)
      end
    end
  end
end

# Use the EXAMS constant from your webserver and append 'de'
exams_dir = File.join(File.dirname(__FILE__), 'exams', 'de')
rename_png_files(exams_dir) 