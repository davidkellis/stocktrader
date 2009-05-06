require 'stats'
require 'pp'
require 'activesupport'
require 'extrb'

# deprecated
module BarConversions
  def to_bars(seconds_per_bar)
    # assumes self is in seconds
    self.to_i / seconds_per_bar
  end
end

class Fixnum
  include BarConversions
end

class Float
  include BarConversions
end

class Bar
  attr_accessor :timestamp, :date, :time, :open, :high, :low, :close
  
  class << self
    def timestamp(date, time)
      "#{date}#{time}"
    end
  end
  
  def initialize(date='0', time='0', open=0, high=0, low=0, close=0)
    self.timestamp = Bar.timestamp(date, time).to_i
    self.date = date
    self.time = time
    self.open = open.to_f
    self.high = high.to_f
    self.low = low.to_f
    self.close = close.to_f
  end
  
  def to_s
    "#{self.timestamp} : #{self.date} @ #{self.time} - #{self.close}"
  end
end

class PriceHistory < Array
  def initialize(filename)
    lines = File.readlines(filename)
    lines.each do |line|
      # record format: Date,Time,Open,High,Low,Close
      self << Bar.new(*line.strip.split(','))
    end
  end
  
  def search_index(timestamp, not_found = :before)
    #assumes the array is sorted in order of ascending timestamp
    interpolationSearch(timestamp, not_found, extractor = ->(bar){ bar.timestamp })
  end
  
  def search(timestamp, not_found = :before)
    #assumes the array is sorted in order of ascending timestamp
    i = interpolationSearch(timestamp, not_found, extractor = ->(bar){ bar.timestamp })
    #puts "i = #{i ? i : 'nil'} ; i && self[i] = #{i && self[i]}" if $DEBUG
    i && self[i]
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
  
  def remove_price_history(*tickers)
    tickers.each do |t|
      @price_histories[t] = nil
    end
  end
  
  def bar(ticker, timestamp)
    price_histories[ticker].search(timestamp) || Bar.new     # Note: the OR expression is a fix for when there is not enough data
  end
  
  def quote(ticker, timestamp)
    #puts "quote: #{ticker} #{timestamp} #{bar(ticker, timestamp).inspect}" if $DEBUG
    bar(ticker, timestamp).close
  end
end

class Broker
  attr_reader :buy_commission, :sell_commission, :exchange
  
  def initialize(exchange, buy_commission, sell_commission = buy_commission)
    @buy_commission = buy_commission
    @sell_commission = sell_commission
    @exchange = exchange
  end
  
  def new_account(cash)
    Account.new(self, cash)
  end
  
  # buy as much as possible [with the given amount]
  def buy_amap(account, ticker, timestamp, amount = nil)
    amount ||= account.cash
    amount = [amount, account.cash].min
    quote = exchange.quote(ticker, timestamp)
    max_shares = ((amount - buy_commission) / quote).floor
    cost = quote * max_shares
    if max_shares > 0 && account.cash >= cost + buy_commission
      #buy(account, ticker, max_shares, timestamp)
      account.cash -= (cost + buy_commission)
      account.portfolio[ticker] += max_shares
      account.commission_paid += buy_commission
      #puts "bought #{max_shares} of #{ticker} on #{timestamp}"
      max_shares    # return the number of shares bought
    else
      0
    end
  end
  
  # buy a number of shares or none at all
  def buy(account, ticker, shares, timestamp)
    cost = exchange.quote(ticker, timestamp) * shares
    if cost >= 0 && account.cash >= cost + buy_commission
      account.cash -= (cost + buy_commission)
      account.portfolio[ticker] += shares
      account.commission_paid += buy_commission
      shares    # return the number of shares bought
    else
      0         # return that 0 shares were bought
    end
  end
  
  def sell_all(account, ticker, timestamp)
    sell(account, ticker, account.portfolio[ticker], timestamp)
  end
  
  # sell a number of shares, up to the number in the portfolio
  def sell(account, ticker, shares, timestamp)
    shares = [shares, account.portfolio[ticker]].min
    gross_profit = exchange.quote(ticker, timestamp) * shares
    post_sale_cash_balance = account.cash + gross_profit
    if(gross_profit >= 0 && post_sale_cash_balance >= sell_commission && account.portfolio[ticker] > 0 && shares > 0)
      account.cash = post_sale_cash_balance - sell_commission
      account.portfolio[ticker] -= shares
      account.commission_paid += sell_commission
      #puts "sold #{shares} of #{ticker} on #{timestamp}"
      shares
    else
      0         # return that 0 shares were sold
    end
  end
  
  def bar(ticker, timestamp)
    exchange.bar(ticker, timestamp)
  end
  
  def quote(ticker, timestamp)
    exchange.quote(ticker, timestamp)
  end
end

class Account
  attr_accessor :portfolio
  attr_accessor :cash
  attr_accessor :broker
  attr_accessor :commission_paid

  def initialize(broker, cash)
    @broker = broker
    @cash = cash.to_f
    @portfolio = Hash.new(0)
    @commission_paid = 0
  end

  # buy as much as possible [with the given amount]
  def buy_amap(ticker, timestamp, amount = nil)
    broker.buy_amap(self, ticker, timestamp, amount)
  end
  
  # buy a number of shares or none at all
  def buy(ticker, shares, timestamp)
    broker.buy(self, ticker, shares, timestamp)
  end
  
  # sell all shares held of a stock - completely liquidate the holdings of a particular ticker symbol
  def sell_all(ticker, timestamp)
    broker.sell_all(self, ticker, timestamp)
  end

  # sell a number of shares, up to the number in the portfolio
  def sell(ticker, shares, timestamp)
    broker.sell(self, ticker, shares, timestamp)
  end
  
  def value(timestamp)
    stock_value = 0
    portfolio.each_pair do |ticker, shares|
      stock_value += broker.exchange.quote(ticker, timestamp) * shares
    end
    cash + stock_value
  end
  
  def to_s(timestamp = 9999_99_99_99_99_99)
    "cash: #{cash}\n" +
      "commission_paid: #{commission_paid}\n" +
      "portfolio holdings as of #{timestamp}: #{portfolio.inspect}\n" +
      "value: #{value(timestamp)}"
  end
end

class Strategy
  TRADING_DAYS = [1, 5]                               # Monday-Friday
  TRADING_HOURS = [8.hours + 30.minutes, 15.hours]    # 8:30 AM CST to 4:00 PM (15:00) CST
  
  attr_reader :account
  attr_reader :tickers_to_trade
  attr_reader :amount_per_company
  attr_writer :verbose
  
  def initialize(account, tickers_to_trade)
    @account = account
    @tickers_to_trade = tickers_to_trade
    @amount_per_company = @account.cash / @tickers_to_trade.length
    @verbose = false
  end
  
  # time_end > time_start
  def run(time_start, time_end, time_increment_in_seconds = 1.day)
    t = time_start
    
    #Make sure the markets are open for trading:
    # ensure that timestamp is within a valid trading period
    t = next_trading_period(t) unless within_trading_days?(t) && within_trading_hours?(t)
    
    while(t <= time_end)
      #recompute the amount we can invest in each company during this round of investing
      @amount_per_company = account.cash / tickers_to_trade.length
      
      for ticker in tickers_to_trade
        trade(ticker, t.to_timestamp.to_i)
      end
      
      t += time_increment_in_seconds
      
      t = next_trading_period(t) unless within_trading_days?(t) && within_trading_hours?(t)
    end
  end
  
  def next_trading_period(t)
    ntp = t
    if within_trading_days?(t)
      t_cmp = t.hour.hours + t.min.minutes + t.sec
      if t_cmp < TRADING_HOURS[0]
        # if t is a weekday and is before the start of trading hours, set ntp to the start of the trading hours for that day
        ntp = t.midnight + TRADING_HOURS[0]
      elsif t_cmp > TRADING_HOURS[1]
        if t.wday == TRADING_DAYS[1]
          # if t is the last day in the trading week and is after the end of trading hours, 
          #   set ntp to the first trading day of the following week
          ntp = t + (TRADING_DAYS[0] + (7 - t.wday)).days
        else
          # if t is a weekday (but not the last day in the trading week) and is after the end of trading hours,
          #   set ntp to the following day
          ntp = t + 1.day
        end
        # set ntp to the start of the trading hours for the weekday that it represents
        ntp = ntp.midnight + TRADING_HOURS[0]
      end
    else
      if t.wday < TRADING_DAYS[0]
        # if t is one of the days before the first day in the trading week (e.g. Sunday),
        #   set ntp to the first day of this trading week
        ntp = t + (TRADING_DAYS[0] - t.wday).days
      elsif t.wday > TRADING_DAYS[1]
        # if t is one of the days after the last day in the trading week (e.g. Saturday),
        #   set ntp to the first trading day of the following week
        ntp = t + (TRADING_DAYS[0] + (7 - t.wday)).days
      end
      # set ntp to the start of the trading hours for the weekday that it represents
      ntp = ntp.midnight + TRADING_HOURS[0]
    end
    ntp
  end
  
  def within_trading_days?(t)
    # is the day of the week Monday through Friday?
    TRADING_DAYS[0] <= t.wday && t.wday <= TRADING_DAYS[1]
  end
  
  def within_trading_hours?(t)
    # is the current time between 9:30 ET and 4:00 ET
    
    #start_of_day = t.midnight
    #(start_of_day + 9.5.hours) <= t && t <= (start_of_day + 16.hours)
    
    t_cmp = t.hour.hours + t.min.minutes + t.sec
    TRADING_HOURS[0] <= t_cmp && t_cmp <= TRADING_HOURS[1]
  end
  
  def verbose?
    @verbose
  end
end
