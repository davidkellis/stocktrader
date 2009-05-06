require 'yahoofinance'
require 'pp'

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

time_interval = 365 * 30

for ticker in tickers
  File.open("#{ticker}.csv", "w+") do |f|
    YahooFinance::get_historical_quotes_days(ticker, time_interval) do |row|
      f.write "#{row.join(',')}\n"
    end
  end
end
