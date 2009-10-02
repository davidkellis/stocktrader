$:.unshift File.join(File.dirname(__FILE__), 'experiments')

require 'randomized_buy_and_hold'
require 'randomized_lucky_indicator'
require 'expectation_mean'

def main
  #$DEBUG = true
  #srand(12344)
end

def buy_and_hold
  scalable_randomized_buy_and_hold
end

def bh_vs_lucky
  scalable_randomized_lucky_indicator(File.join(File.dirname(__FILE__), 'experiments', 'buyandholdresults_sp500_10_years.csv'))
end

def extract_first_last_lines_compute_gain
  tickers = ARGV.map {|t| t.upcase.chomp('.CSV') }
  
  max_trading_period = 3650.days    # 2 days short of 10 years
  first_and_last_lines = ->(filename) { [File.new(filename).gets, File::ReadBackwards.new(filename).gets] }
  get_fields = ->(line,*fields) { line.strip.split(',').values_at(*fields) }
  get_close = ->(line) { get_fields.(line, 5).first.to_f }
  last_over_first = ->(ticker) do
    lines = first_and_last_lines.("#{ticker}.csv")
    prices = lines.map(&get_close)
    [ticker,lines,prices.last.to_f/prices.first]
  end
  tickers.map(&last_over_first).sort(){|triple1, triple2| triple1[2]<=>triple2[2] }.each{|triple| pp triple }
end

def expectation_value
  scalable_randomized_expectation_mean
end

#$DEBUG = true

#main
#extract_first_last_lines_compute_gain

#buy_and_hold
#bh_vs_lucky
expectation_value