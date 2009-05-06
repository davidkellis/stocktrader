require 'stats'
require 'pp'

class EODData
  attr_accessor :date, :open, :high, :low, :close, :volume, :adj_close
  
  def initialize(date, open, high, low, close, volume, adj_close)
    self.date = date
    self.open = open.to_f
    self.high = high.to_f
    self.low = low.to_f
    self.close = close.to_f
    self.volume = volume.to_i
    self.adj_close = adj_close.to_f
  end
end

class PriceHistory
  attr_accessor :history
  
  def initialize(filename)
    @history = Array.new
    lines = File.readlines(filename)
    lines.each do |line|
      # record format: Date,Open,High,Low,Close,Volume,Adj Close
      @history << EODData.new(*line.strip.split(','))
    end
  end
  
  def [](i)
    @history[i]
  end
end

class Exchange
  attr_accessor :price_histories
  
  def initialize(*tickers)
    @price_histories = Hash.new
    tickers.each do |t|
      @price_histories[t] = PriceHistory.new("#{t}.csv")
    end
  end
  
  def add_price_history(*tickers)
    tickers.each do |t|
      @price_histories[t] = PriceHistory.new("#{t}.csv")
    end
  end
  
  def eod(ticker, days_ago)
    days_ago = [1, days_ago].max
    @price_histories[ticker][days_ago - 1] || EODData.new(-1,-1,-1,-1,-1,-1,-1)     # Note: the OR expression is a fix for when there is not enough data
  end
  
  def quote(ticker, days_ago)
    eod(ticker, days_ago).adj_close
  end
  
  def eod_between(ticker, days_ago_recent, days_ago_oldest)
    @price_histories[ticker][(days_ago_recent - 1)..(days_ago_oldest - 1)] || []    # Note: the OR expression is a fix for when there is not enough data
  end
end

class Broker
  attr_reader :buy_commission, :sell_commission, :exchange
  
  def initialize(exchange, commission)
    @buy_commission = commission
    @sell_commission = commission
    @exchange = exchange
  end
  
  def new_account(cash)
    Account.new(self, cash)
  end
  
  # buy as much as possible [with the given amount]
  def buy_amap(account, ticker, days_ago, amount = nil)
    amount ||= account.cash
    amount = [amount, account.cash].min
    max_shares = ((amount - @buy_commission) / @exchange.quote(ticker, days_ago)).floor
    if max_shares > 0
      buy(account, ticker, max_shares, days_ago)
    else
      0
    end
  end
  
  # buy a number of shares or none at all
  def buy(account, ticker, shares, days_ago)
    cost = @exchange.quote(ticker, days_ago) * shares
    if cost >= 0 && account.cash >= cost + @buy_commission
      account.cash -= (cost + @buy_commission)
      account.portfolio[ticker] += shares
      account.commission_paid += @buy_commission
      shares    # return the number of shares bought
    else
      0         # return that 0 shares were bought
    end
  end
  
  def sell_all(account, ticker, days_ago)
    sell(account, ticker, account.portfolio[ticker], days_ago)
  end
  
  # sell a number of shares, up to the number in the portfolio
  def sell(account, ticker, shares, days_ago)
    shares = [shares, account.portfolio[ticker]].min
    gross_profit = @exchange.quote(ticker, days_ago) * shares
    post_sale_cash_balance = account.cash + gross_profit
    if(gross_profit >= 0 && post_sale_cash_balance >= @sell_commission && account.portfolio[ticker] > 0 && shares > 0)
      account.cash = post_sale_cash_balance - @sell_commission
      account.portfolio[ticker] -= shares
      account.commission_paid += @sell_commission
      shares
    else
      0         # return that 0 shares were sold
    end
  end
end

class Account
  attr_accessor :portfolio
  attr_accessor :cash
  attr_accessor :broker
  attr_accessor :commission_paid
  #attr_accessor :transactions

  def initialize(broker, cash)
    @broker = broker
    @cash = cash.to_f
    @portfolio = Hash.new(0)
    @commission_paid = 0
    #@transactions = Hash.new
  end

  # buy as much as possible [with the given amount]
  def buy_amap(ticker, days_ago, amount = nil)
    @broker.buy_amap(self, ticker, days_ago, amount)
  end
  
  # buy a number of shares or none at all
  def buy(ticker, shares, days_ago)
    @broker.buy(self, ticker, shares, days_ago)
  end
  
  # sell all shares held of a stock - completely liquidate the holdings of a particular ticker symbol
  def sell_all(ticker, days_ago)
    @broker.sell_all(self, ticker, days_ago)
  end

  # sell a number of shares, up to the number in the portfolio
  def sell(ticker, shares, days_ago)
    @broker.sell(self, ticker, shares, days_ago)
  end
  
  def value(day)
    stock_value = 0
    @portfolio.each_pair do |ticker, shares|
      stock_value += @broker.exchange.quote(ticker, day) * shares
    end
    @cash + stock_value
  end
  
  def to_s(day = 1)
    "cash: #{cash}\ncommission_paid: #{commission_paid}\nportfolio holdings as of #{day} days ago: #{portfolio.inspect}\nvalue: #{value(day)}"
  end
end

class Strategy
  def initialize(account, tickers_to_trade)
    @account = account
    @tickers = tickers_to_trade
    @amount_per_company = @account.cash / @tickers.length
  end
  
  # start_day is a larger number than end_day
  def run(start_day, end_day = 1)
    day = start_day
    while(day >= end_day)
      #recompute the amount we can invest in each company during this round of investing
      @amount_per_company = @account.cash / @tickers.length
      
      for ticker in @tickers
        trade(ticker, day)
      end
      
      day -= 1    # move one day ahead
    end
  end
end

class BuyAndHoldStrategy < Strategy
  # averaging_period must be >= 1 day
  def initialize(account, tickers_to_trade, last_day_to_hold)
    super(account, tickers_to_trade)
    
    @last_day_to_hold = last_day_to_hold
    #@amount_per_company = @account.cash / @tickers.length
  end

  def trade(ticker, day)
    if(@account.cash > 0)
      s = @account.buy_amap(ticker, day, @amount_per_company)
      puts "bought #{s} shares of #{ticker} on #{@account.broker.exchange.eod(ticker, day).date}" if $DEBUG
    end
    if(day == @last_day_to_hold)
      s = @account.sell_all(ticker, day)
      puts "sold #{s} shares of #{ticker} on #{@account.broker.exchange.eod(ticker, day).date}" if $DEBUG
    end
  end

  def to_s
    "Buy-And-Hold:\n" +
    "  Last Day to Hold: #{@last_day_to_hold}\n" +
    "  Tickers: #{@tickers.join(', ')}\n" +
    "  Account: #{@account.to_s}"
  end
  
  def parameter_set
    "Buy-and-Hold: last day to hold: #{@last_day_to_hold}"
  end
end

# compare this strategy with the charts on http://stockcharts.com/h-sc/ui
class SMAStrategy < Strategy
  # averaging_period must be >= 1 day
  def initialize(account, tickers_to_trade, averaging_period)
    super(account, tickers_to_trade)
    
    @averaging_period = averaging_period
    @sums = Hash.new
    @price_relation_to_average = Hash.new(0)
    #@amount_per_company = @account.cash / @tickers.length
  end
  
  def trade(ticker, day)
    # compute average over number of days
    avg = average_price(ticker, day)
    
    puts "avg price of #{ticker} on #{@account.broker.exchange.eod(ticker, day).date} is #{avg}" if $DEBUG
    
    # this day's price
    price = @account.broker.exchange.quote(ticker, day)

    puts "price of #{ticker} on #{@account.broker.exchange.eod(ticker, day).date} is #{price}" if $DEBUG
    
    # if price > avg  ->  price - avg = positive
    #    price < avg  ->  price - avg = negative
    #    price = avg  ->  price - avg = 0
    @price_relation_to_average["#{ticker}#{day}"] = price - avg
    
    puts "price relation to avg day before is #{@price_relation_to_average["#{ticker}#{day + 1}"]}" if $DEBUG
    
    # decide whether the price has just upcrossed or downcrossed the MA line
    if(price > avg && @price_relation_to_average["#{ticker}#{day + 1}"] < 0)        # upcross - BUY as much as possible
      s = @account.buy_amap(ticker, day, @amount_per_company)
      puts "bought #{s} shares of #{ticker} on #{@account.broker.exchange.eod(ticker, day).date}" if $DEBUG
    elsif(price < avg && @price_relation_to_average["#{ticker}#{day + 1}"] > 0)     # downcross - SELL all shares
      s = @account.sell_all(ticker, day)
      puts "sold #{s} shares of #{ticker} on #{@account.broker.exchange.eod(ticker, day).date}" if $DEBUG
    end
    
    puts "account: #{@account.to_s(day)}" if $DEBUG
  end
  
  def average_price(ticker, origin_day)
    tmp = @sums["#{ticker}#{origin_day + 1}"]
    if tmp
      tmp -= @account.broker.exchange.quote(ticker, origin_day + @averaging_period)
      tmp += @account.broker.exchange.quote(ticker, origin_day)
      @sums["#{ticker}#{origin_day}"] = tmp
    else
      @sums["#{ticker}#{origin_day}"] = @account.broker.exchange.eod_between(ticker, origin_day, origin_day + @averaging_period - 1).reduce(0) { |sum,eod| sum += eod.adj_close }
    end
    
    # return the average price
    @sums["#{ticker}#{origin_day}"].to_f / @averaging_period
  end

  def to_s
    "SMA:\n" +
    "  Averaging Period: #{@averaging_period}\n" +
    "  Tickers: #{@tickers.join(', ')}\n" +
    "  Account: #{@account.to_s}"
  end

  def parameter_set
    "SMA: averaging period: #{@averaging_period}"
  end
end


class EMAStrategy < Strategy
  # n_periods must be >= 1 day
  def initialize(account, tickers_to_trade, n_periods)
    super(account, tickers_to_trade)
    
    @n_periods = n_periods
    @smoothing_const = 2.0 / (n_periods + 1)
    @emas = Hash.new
    @price_relation_to_average = Hash.new(0)
    #@amount_per_company = @account.cash / @tickers.length
  end
  
  def trade(ticker, day)
    # compute exponential moving average over number of days
    avg = exponential_average_price(ticker, day)
    
    puts "exp avg price of #{ticker} on #{@account.broker.exchange.eod(ticker, day).date} is #{avg}" if $DEBUG
    
    # this day's price
    price = @account.broker.exchange.quote(ticker, day)

    puts "price of #{ticker} on #{@account.broker.exchange.eod(ticker, day).date} is #{price}" if $DEBUG
    
    # if price > avg  ->  price - avg = positive
    #    price < avg  ->  price - avg = negative
    #    price = avg  ->  price - avg = 0
    @price_relation_to_average["#{ticker}#{day}"] = price - avg
    
    puts "price relation to EMA day before is #{@price_relation_to_average["#{ticker}#{day + 1}"]}" if $DEBUG
    
    # decide whether the price has just upcrossed or downcrossed the MA line
    if(price > avg && @price_relation_to_average["#{ticker}#{day + 1}"] < 0)        # upcross - BUY as much as possible
      s = @account.buy_amap(ticker, day, @amount_per_company)
      puts "bought #{s} shares of #{ticker} on #{@account.broker.exchange.eod(ticker, day).date}" if $DEBUG
    elsif(price < avg && @price_relation_to_average["#{ticker}#{day + 1}"] > 0)     # downcross - SELL all shares
      s = @account.sell_all(ticker, day)
      puts "sold #{s} shares of #{ticker} on #{@account.broker.exchange.eod(ticker, day).date}" if $DEBUG
    end
    
    puts "account: #{@account.to_s(day)}" if $DEBUG
  end
  
  # implementation notes:
  # http://stockcharts.com/school/doku.php?id=chart_school:technical_indicators:moving_averages#uses_for_moving_aver
  # http://en.wikipedia.org/wiki/Moving_average
  def exponential_average_price(ticker, origin_day)
    ema_prev = @emas["#{ticker}#{origin_day + 1}"] || simple_average_price(ticker, origin_day)
    price = @account.broker.exchange.quote(ticker, origin_day)
    
    @emas["#{ticker}#{origin_day}"] = ema_prev + @smoothing_const * (price - ema_prev)
  end
  
  def simple_average_price(ticker, origin_day)
    sum = @account.broker.exchange.eod_between(ticker, origin_day, origin_day + @n_periods - 1).reduce(0) { |sum,eod| sum += eod.adj_close }
    sum.to_f / @n_periods
  end
  
  def to_s
    "EMA:\n" +
    "  N-Period: #{@n_periods}\n" +
    "  Alpha (smoothing const): #{@smoothing_const}\n" +
    "  Tickers: #{@tickers.join(', ')}\n" +
    "  Account: #{@account.to_s}"
  end
  
  def parameter_set
    "EMA: n-period: #{@n_periods}, alpha: #{@smoothing_const}"
  end
end


def experiment
  tickers = ARGV.map {|t| t.upcase.chomp('.CSV') }
  
  sample_size = 10
  portfolio_size = 5
  commission_fees = 7.00
  initial_deposit = 100000
  
  e = Exchange.new()
  scottrade = Broker.new(e, commission_fees)
  best_strategies = Hash.new
  
  # randomize the order of the ticker symbols
  #srand(1234)
  tickers.shuffle!
  
  # this creates a sample of ticker sets (which have been randomized)
  ticker_sets = tickers.each_slice(portfolio_size).to_a.slice(0...sample_size)
  
  puts "Portfolios of stocks:"
  p ticker_sets
  
  trading_period_in_days = 365
  avg_period = 98
  n_period = 200
  null_hypothesis_mean = 0
  confidence_interval = 0.95      # we want a 95% confidence interval
  significance_level = 1 - confidence_interval
  
  strategy_differences = ticker_sets.map do |ticker_set|
    # NOTE: A ticker_set is a portfolio of stocks that are treated as an independent unit
    
    e.add_price_history(*ticker_set)
    
    # Compute value of portfolio using Buy-And-Hold strategy
    # Buy as soon as possible (365 days ago -> trading_period_in_days) and sell when the simulation day becomes yesterday (1 day ago)
    bah_account = scottrade.new_account(initial_deposit)
    bah = BuyAndHoldStrategy.new(bah_account, ticker_set, 0)
    bah.run(trading_period_in_days)
    
    # Compute value of portfolio using SMA strategy
    sma_account = scottrade.new_account(initial_deposit)
    sma = SMAStrategy.new(sma_account, ticker_set, avg_period)
    sma.run(trading_period_in_days)

    # Compute value of portfolio using SMA strategy
    #ema_account = scottrade.new_account(initial_deposit)
    #ema = EMAStrategy.new(ema_account, ticker_set, n_period)
    #ema.run(trading_period_in_days)
    
    # compute values of accounts as of one day ago
    diff = sma_account.value(1) - bah_account.value(1)
    #diff = ema_account.value(1) - bah_account.value(1)
    puts "#{ticker_set} portfolio difference between sma and buy-and-hold is #{diff}"
    #puts "#{ticker_set} portfolio difference between ema and buy-and-hold is #{diff}"
    diff
  end
  
  # Null Hypothesis is that there is no effect of switching strategies from the default Buy-and-Hold to the SMA.
  # That is, the average value of the differences (i.e. Buy-and-Hold portfolio value - SMA portfolio value) is 0.
  t = strategy_differences.sample_t_statistic(null_hypothesis_mean)
  puts "t-statistic is #{t}"
  puts "degrees of freedom is #{strategy_differences.length - 1}"
  
  p_value = strategy_differences.two_tailed_p_score(t, strategy_differences.length - 1)
  puts "Two-tailed p-value is #{p_value}"
  
  # we reject the null hypothesis when the p-value is less than or equal to the pre-selected significance level
  if(p_value <= significance_level)
    puts "Reject the null hypothesis. There is a statistically significant difference between the average buy-and-hold strategy return and the average SMA strategy return."
  else
    puts "Do NOT reject the null hypothesis. There is NOT a statistically significant difference between the average buy-and-hold strategy return and the average SMA strategy return."
  end
end

def performance
  tickers = ARGV.map {|t| t.upcase.chomp('.CSV') }
  
  sample_size = 10
  portfolio_size = 5
  commission_fees = 7.00
  initial_deposit = 100000
  max_averaging_period = 200
  max_n_period = 200
  trading_period_in_days = 365
  #best_strategies_per_portfolio = Hash.new
  number_of_best_strategies_per_portfolio = 3
  
  # randomize the order of the ticker symbols
  #srand(1234)
  tickers.shuffle!
  
  # this creates a sample of ticker sets (which have been randomized)
  ticker_sets = tickers.each_slice(portfolio_size).to_a.slice(0...sample_size)
  
  puts "Portfolios of stocks:"
  p ticker_sets
  puts
  
  e = Exchange.new()
  scottrade = Broker.new(e, commission_fees)
  best_strategies = Hash.new
  count_of_like_strategies = Hash.new(0)
  
  ticker_sets.each do |ticker_set|
    # NOTE: A ticker_set is a portfolio of stocks that are treated as an independent unit

    # load the exchange up with price history just-in-time style
    e.add_price_history(*ticker_set)

    all_strategies = Hash.new

    # Test SMA
    2.upto(max_averaging_period).each do |avg_period|
      # Compute value of portfolio using SMA strategy
      a = scottrade.new_account(initial_deposit)
      sma = SMAStrategy.new(a, ticker_set, avg_period)
      sma.run(trading_period_in_days)
      all_strategies[sma] = a.value(1)
      #puts "Averaging Period: #{avg_period}",a.to_s(1),'***************************************************************'
    end

    # Test EMA
    2.upto(max_n_period).each do |n_period|
      a = scottrade.new_account(initial_deposit)
      ema = EMAStrategy.new(a, ticker_set, n_period)
      ema.run(trading_period_in_days)
      all_strategies[ema] = a.value(1)
      #puts "N-Period: #{n_period}",a.to_s(1),'***************************************************************'
    end

    # Compute value of portfolio using Buy-And-Hold strategy
    # Buy as soon as possible (365 days ago -> trading_period_in_days) and sell when the simulation day becomes yesterday (1 day ago)
    a = scottrade.new_account(initial_deposit)
    bah = BuyAndHoldStrategy.new(a, ticker_set, 0)
    bah.run(trading_period_in_days)
    all_strategies[bah] = a.value(1)
    #puts "Buy-And-Hold: ",a.to_s(1),'***************************************************************'

    # Sort the strategies by overall performance and output the best 5
    sorted_strategies = all_strategies.sort {|a,b| b[1] <=> a[1] }  # a,b[0] -> key ; a,b[1] -> stored value
    # sorted_strategies is an Array of pairs (i.e. each pair is an array with two elements)
    # sorted_strategies[0...10].each { |pair| puts pair[0],'*******************' }

    #best_strategies_per_portfolio[ticker_set.join(',')] = sorted_strategies[0...number_of_best_strategies_per_portfolio]

    best_strategies = sorted_strategies[0...number_of_best_strategies_per_portfolio]
    puts "portfolio: #{ticker_set.join(',')}"
    puts "best strategies:"
    for strategy_value_pair in best_strategies
      count_of_like_strategies[strategy_value_pair[0].parameter_set] += 1
      puts "value: #{strategy_value_pair[1]}",strategy_value_pair[0],"-----"
    end
    puts "\n"
  end
  
  pp count_of_like_strategies
  
=begin
  best_strategies_per_portfolio.each do |ticker_set,best_strategies|
    puts "portfolio: #{ticker_set}"
    puts "best strategies:"
    for strategy_value_pair in best_strategies
      puts "value: #{strategy_value_pair[1]}",strategy_value_pair[0],"-----"
    end
    puts "\n"
  end
=end
end

def brute_force_avg
  tickers = ARGV.map {|t| t.upcase.chomp('.CSV') }
  
  sample_size = 10
  portfolio_size = 1
  commission_fees = 7.00
  initial_deposit = 100000
  max_averaging_period = 200
  max_n_period = 200
  trading_period_in_days = 365
  last_day_of_trading_range = 1266...(1266+365)
  
  # randomize the order of the ticker symbols
  #srand(1234)
  tickers.shuffle!
  
  # this creates a sample of ticker sets (which have been randomized)
  ticker_sets = tickers.each_slice(portfolio_size).to_a.slice(0...sample_size)
  
  puts "Portfolios of stocks:"
  p ticker_sets
  puts
  
  e = Exchange.new()
  scottrade = Broker.new(e, commission_fees)
  average_values = Hash.new
  
  ticker_sets.each do |ticker_set|
    # NOTE: A ticker_set is a portfolio of stocks that are treated as an independent unit
    
    # load the exchange up with price history just-in-time style
    e.add_price_history(*ticker_set)
    
    sma_strategies = Hash.new
    ema_strategies = Hash.new
    bah_strategies = Hash.new
    
    for last_day_of_trading in last_day_of_trading_range
      # Test SMA
      2.upto(max_averaging_period).each do |avg_period|
        # Compute value of portfolio using SMA strategy
        a = scottrade.new_account(initial_deposit)
        sma = SMAStrategy.new(a, ticker_set, avg_period)
        sma.run(last_day_of_trading + trading_period_in_days - 1, last_day_of_trading)
        sma_strategies["SMA,#{last_day_of_trading},#{trading_period_in_days},#{avg_period}"] = a.value(last_day_of_trading)
        #puts "Averaging Period: #{avg_period}",a.to_s(1),'***************************************************************'
      end
      
      # Test EMA
      2.upto(max_n_period).each do |n_period|
        a = scottrade.new_account(initial_deposit)
        ema = EMAStrategy.new(a, ticker_set, n_period)
        ema.run(last_day_of_trading + trading_period_in_days - 1, last_day_of_trading)
        ema_strategies["EMA,#{last_day_of_trading},#{trading_period_in_days},#{n_period}"] = a.value(last_day_of_trading)
        #puts "N-Period: #{n_period}",a.to_s(1),'***************************************************************'
      end
      
      # Compute value of portfolio using Buy-And-Hold strategy
      a = scottrade.new_account(initial_deposit)
      bah = BuyAndHoldStrategy.new(a, ticker_set, 0)
      bah.run(last_day_of_trading + trading_period_in_days - 1, last_day_of_trading)
      bah_strategies["BaH,#{last_day_of_trading},#{trading_period_in_days}"] = a.value(last_day_of_trading)
      #puts "Buy-And-Hold: ",a.to_s(1),'***************************************************************'
    end
    
    average_values[ticker_set.join(',')] = {:avg_value_sma => sma_strategies.values.mean,
                                            :std_dev_sma => sma_strategies.values.sample_std_dev,
                                            :avg_value_ema => ema_strategies.values.mean,
                                            :std_dev_ema => ema_strategies.values.sample_std_dev,
                                            :avg_value_bah => bah_strategies.values.mean,
                                            :std_dev_bah => bah_strategies.values.sample_std_dev}
  end
  
  pp average_values
end


#$DEBUG = true

#performance
#experiment
brute_force_avg