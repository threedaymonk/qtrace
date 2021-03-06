require 'active_record/connection_adapters/abstract_adapter'
class ActiveRecord::ConnectionAdapters::AbstractAdapter
  alias_method :__rails_standard_log, :log
  
  def log(sql, name, &blk)
    sql_without_newlines = sql.gsub(/\s*\n\s*/, ' ')
    if QTrace.match?(sql_without_newlines)
      ([sql_without_newlines] + caller).each do |line|
        RAILS_DEFAULT_LOGGER.debug('** '+line) unless line =~ %r{/rails/|/lib/ruby/}
      end
    end
    t0 = Time.now
    ret = __rails_standard_log(sql, name, &blk)
    QTrace.record(sql_without_newlines, Time.now - t0)
    ret
  end
end

class QTrace
  class << self
    
    def sql?(line)
      return line =~ /SQL \(/
    end
    
    def record(sql, time)
      case sql
      when /INSERT INTO (\`.+?\`|([^ ]+))/
        cmd = 'insert'
        tbl = $2 || $1
      when /SELECT .*? FROM (\`.+?\`|([^ ]+))/
        cmd = 'select'
        tbl = $2 || $1
      when /UPDATE (\`.+?\`|([^ ]+))/
        cmd = 'update'
        tbl = $2 || $1
      else
        return
      end
      tbl.gsub!(/^\`|\`$/, '')
      key = cmd + ' ' + tbl
      statistics[key] ||= [0,0]
      statistics[key][0] += 1
      statistics[key][1] += time
    end
    
    def statistics
      @statistics ||= {}
    end
    
    def watch(pattern)
      @regexp = nil
      unless pattern.is_a?(Regexp)
        pattern = Regexp.escape(pattern.to_s)
      end
      patterns << pattern
    end
    
    def patterns
      @patterns ||= []
    end
    
    def regexp
      @regexp ||= Regexp.new(patterns.uniq.join('|'), Regexp::IGNORECASE)
    end
    
    def match?(sql)
      patterns.any? && sql.match(regexp)
    end
    
    def show_statistics
      puts '', 'QTrace statistics', ''
      print_report(
        [['Request', 'No. calls', 'Time']] + 
        statistics.sort_by{ |key, (calls, time)| calls }.reverse.map{ |r| [r[0], r[1][0], "%.04f" % r[1][1]] } +
        [['Total', 
          statistics.inject(0){ |acc, (key, (calls, time))| acc + calls },
          ("%.04f" % statistics.inject(0){ |acc, (key, (calls, time))| acc + time  })]]
      )
    end
    
    def print_report(data)
      widths = []
      data.each do |row|
        row.each_with_index do |cell, column_index|
          cell_data_length = cell.to_s.length
          widths[column_index] = cell_data_length if widths[column_index].nil? || cell_data_length > widths[column_index]
        end
      end
      data.each_with_index do |row, row_index|
        row.each_with_index do |cell, column_index|
          cell_data = cell.to_s
          cell_data = if (cell_data =~ /^[\d\.%]+$/)
            cell_data.rjust(widths[column_index])
          else
            cell_data.ljust(widths[column_index])
          end
          print('| %s ' % cell_data)
        end
        puts('|')
      end
    end

    def load_watchers
      path = File.join(Rails.root, 'config', 'qtrace.rb')
      require path if File.exist?(path)
    end
    
  end
end

QTrace.load_watchers

END { QTrace.show_statistics }
