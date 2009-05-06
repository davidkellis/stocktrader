$:.unshift File.join(File.dirname(__FILE__), '..')

require 'simulator.rb'

class BuyAndHoldStrategy < Strategy
  def initialize(account, tickers_to_trade, timestamp_to_sell)
    super(account, tickers_to_trade)
    
    @timestamp_to_sell = timestamp_to_sell
  end
  
  def trade(ticker, timestamp)
    if(account.cash > 0)
      s = account.buy_amap(ticker, timestamp, amount_per_company)
      #if verbose?
        #b = account.broker.exchange.bar(ticker, timestamp)
        #puts "buying shares of #{ticker} at #{timestamp} -> #{b.inspect}"
        #puts "bought #{s} shares of #{ticker} on #{b.date} at #{b.time}  (timestamp=#{timestamp})"
      #end
    end
    if(timestamp == @timestamp_to_sell)
      s = account.sell_all(ticker, timestamp)
      #if verbose?
        #b = account.broker.exchange.bar(ticker, timestamp)
        #puts "selling shares of #{ticker} at #{timestamp} -> #{b.inspect}"
        #puts "sold #{s} shares of #{ticker} on #{b.date} at #{b.time} (timestamp=#{timestamp})"
      #end
    end
  end
  
  def to_s
    "Buy-And-Hold:\n" +
    "  Last Bar to Hold: #{@timestamp_to_sell}\n" +
    "  Tickers: #{tickers_to_trade.join(', ')}\n" +
    "  Account: #{account.to_s}"
  end
  
  def parameter_set
    "Buy-and-Hold: last bar to hold: #{@timestamp_to_sell}"
  end
end