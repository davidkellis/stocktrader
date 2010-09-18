require 'yahoofinance'
require 'pp'

# Convert a yahoo format to tradestation format.
# Converts
#   [date, open, high, low, close, volume, adj-close]
# to
#   [date, 150000, open, high, low, adj-close]
# Note: Modifies the original record/array.
def yahoo_to_default!(record)
  record[0].gsub!('-','')
  record.delete_at(4)
  record.delete_at(4)
  record.insert(1, "150000")
end

def main
  # Getting the historical quote data as a raw array.
  # The elements of the array are:
  #   [0] - Date
  #   [1] - Open
  #   [2] - High
  #   [3] - Low
  #   [4] - Close
  #   [5] - Volume
  #   [6] - Adjusted Close

  tickers = if ARGV.length == 0
              %w{BOOM HURC BOLT F}
            elsif ARGV.length == 1
              if ARGV[0].index(/\.\w+/)   # treat as filename
                File.readlines(ARGV[0]).map{|line| line.strip }
              else
                ARGV
              end
            else
              ARGV
            end

  #pp tickers

  time_interval_days = 365 * 31

  for ticker in tickers
    rows = []
    YahooFinance::get_historical_quotes_days(ticker, time_interval_days) do |row|
      rows << "#{yahoo_to_default!(row).join(',')}\n"
    end
    rows.reverse!     # we want to write the file with the oldest quotes first.
    File.open("#{ticker}.csv", "w+") do |f|
      rows.each { |r| f.write r }
    end
  end
end

main