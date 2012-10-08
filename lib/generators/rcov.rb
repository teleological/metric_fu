require 'enumerator'

module MetricFu

  class Rcov < Generator
    NEW_FILE_MARKER = /^={80}$/.freeze

    class Line
      attr_accessor :content, :was_run

      def initialize(content, was_run)
        @content = content
        @was_run = was_run
      end

      def to_h
        {:content => @content, :was_run => @was_run}
      end
    end

    def emit
      # Execute an rcov process if a command is given
      # or if no command is given and no external path is supplied
      if MetricFu.rcov[:command] || !MetricFu.rcov[:external]
        if MetricFu.rcov[:append]
          dirname = File.dirname(output_path)
          FileUtils.rm_rf(dirname, :verbose => false)
          Dir.mkdir(dirname)
        end
        puts "** Running the specs/tests"
        `#{shell_command}`
      end
    end


    def analyze
      output = File.open(output_path).read
      output = output.split(NEW_FILE_MARKER)

      output.shift # Throw away the first entry - it's the execution time etc.

      files = assemble_files(output)

      @global_total_lines = 0
      @global_total_lines_run = 0

      @rcov = add_coverage_percentage(files)
    end

    def to_h
      global_percent_run = ((@global_total_lines_run.to_f / @global_total_lines.to_f) * 100)
      add_method_data
      {:rcov => @rcov.merge({:global_percent_run => round_to_tenths(global_percent_run) })}
    end

    private

    def add_method_data
      @rcov.each_pair do |file_path, info|
        file_contents = ""
        coverage = []

        info[:lines].each_with_index do |line, index|
          file_contents << "#{line[:content]}\n"
          coverage << line[:was_run]
        end

        begin
          line_numbers = MetricFu::LineNumbers.new(file_contents)
        rescue StandardError => e
          raise e unless e.message =~ /you shouldn't be able to get here/
          puts "ruby_parser blew up while trying to parse #{file_path}. You won't have method level Rcov information for this file."
          next
        end

        method_coverage_map = {}
        coverage.each_with_index do |covered, index|
          line_number = index + 1
          if line_numbers.in_method?(line_number)
            method_name = line_numbers.method_at_line(line_number)
            method_coverage_map[method_name] ||= {}
            method_coverage_map[method_name][:total] ||= 0
            method_coverage_map[method_name][:total] += 1
            method_coverage_map[method_name][:uncovered] ||= 0
            method_coverage_map[method_name][:uncovered] += 1 if !covered
          end
        end

        @rcov[file_path][:methods] = {}

        method_coverage_map.each do |method_name, coverage_data|
          @rcov[file_path][:methods][method_name] = (coverage_data[:uncovered] / coverage_data[:total].to_f) * 100.0
        end

      end
    end

    def assemble_files(output)
      files = {}
      output.each_slice(2) {|out| files[out.first.strip] = out.last}
      files.each_pair {|fname, content| files[fname] = content.split("\n") }
      files.each_pair do |fname, content|
        content.map! do |raw_line|
          line = Line.new(raw_line[3..-1], !raw_line.match(/^!!/)).to_h
        end
        content.reject! {|line| line[:content].blank? }
        files[fname] = {:lines => content}
      end
      files
    end

    def add_coverage_percentage(files)
      files.each_pair do |fname, content|
        lines = content[:lines]
        @global_total_lines_run += lines_run = lines.find_all {|line| line[:was_run] == true }.length
        @global_total_lines += total_lines = lines.length
        percent_run = ((lines_run.to_f / total_lines.to_f) * 100).round
        files[fname][:percent_run] = percent_run
      end
    end

    def output_path
      MetricFu.rcov[:external] || File.join(MetricFu::Rcov.metric_directory, "rcov.txt")
    end

    def shell_command
      shell_cmd = ""

      if MetricFu.rcov[:environment]
        shell_cmd << "RAILS_ENV=#{MetricFu.rcov[:environment]} "
      end

      executable = MetricFu.rcov[:command] || 'rcov'
      test_files = FileList[*MetricFu.rcov[:test_files]].join(' ')
      rcov_opts = MetricFu.rcov[:rcov_opts].join(' ')
      shell_cmd << "#{executable} #{test_files} #{rcov_opts}"

      if MetricFu.rcov[:append]
        shell_cmd << " << #{output_path}" 
      end

      shell_cmd
    end

  end
end
