require 'pp'
require 'time'

module FileUtils
  module ClassMethods
    def sort_lines!(filename, remove_duplicate_lines = true, file_extension_suffix = "", &comparator)
      lines = File.readlines(filename)
      lines.uniq! if remove_duplicate_lines
      lines.sort!(&comparator)
      f = File.new("#{filename}#{file_extension_suffix}", 'w')
      lines.each { |l| f.write(l) }
      f.close
    end

    def reverse_lines!(filename)
      lines = File.readlines(filename)
      lines.reverse!
      f = File.new("#{filename}", 'w')
      lines.each { |l| f.write(l) }
      f.close
    end
  end

  def split_and_filter(file_extension, fn_key_map, fn_output_filter)
    open_files = Hash.new
    each do |line|
      key = fn_key_map.call(line)
      out = open_files[key] || File.new("#{key}#{file_extension}", "a")
      out.write(fn_output_filter.call(line))
      open_files[key] = out
    end
    open_files.each { |ticker,file| file.close }
    open_files.map { |ticker,file| File.basename(file.path) }
  end

  def self.included(klass)
    klass.extend(ClassMethods)
  end
end

class File
  include FileUtils
end

def split_ts_export_main
  key_map = ->(line) { line.strip.split(',')[0] }   # split on ticker symbol
  output_filter = ->(line) do
    values = line.strip.split(',').values_at(3..8)
    values[0] = Time.strptime(values[0][values[0].length - 6, 6], "%y%m%d").strftime("%Y%m%d")
    values[1] = values[1].rjust(4,'0') + "00"
    values.join(',') + "\n"
  end
  output_files = File.new(ARGV[0]).split_and_filter(".csv", key_map, output_filter)
  puts output_files.join("\n")
  output_files
end

def sort_lines_main(filelist)
  #fn_timestamp = ->(date, time) { "#{date}#{time.rjust(6,'0')}" }
  fn_timestamp = ->(date, time) { "#{date}#{time}" }
  for filename in filelist
    File.sort_lines!(filename, true) do |line1, line2|
      # ascending order
      fn_timestamp.call(*line1.strip.split(',')[0..1]) <=> fn_timestamp.call(*line2.strip.split(',')[0..1])

      # descending order
      #fn_timestamp.call(*line2.strip.split(',')[0..1]) <=> fn_timestamp.call(*line1.strip.split(',')[0..1])
    end
  end
end

def reverse_lines_main
  File.reverse_lines!(ARGV[0])
end

# this script processed a 29-company 170MB tradestation-export file in 5 minutes, 3 seconds.
# => about 11 seconds to process each company
# => ~3 hours to process 1000 companies
# => ~30 hours to process 10000
def main
  filelist = split_ts_export_main
  sort_lines_main(filelist)
  #reverse_lines_main
end

#main
#split_ts_export_main
sort_lines_main(ARGV)
