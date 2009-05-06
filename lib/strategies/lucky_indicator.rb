$:.unshift File.join(File.dirname(__FILE__), '..')

require 'simulator.rb'
require 'extrb'

# This is the trading strategy that Dr. Rushton told me about and wanted me 
# to implement for my Spring 2009 CS 7000 class.
class LuckyIndicator < Strategy
  def initialize(account, tickers_to_trade, lucky_percentiles_csv, lucky_percentile, percentage_hold_time, hold_time_exp, percentage_price_drop)
    super(account, tickers_to_trade)
    
    @csv_table = lucky_percentiles_csv.is_a?(CSVNumericTable) ? lucky_percentiles_csv : CSVNumericTable.new(lucky_percentiles_csv)
    @lucky_percentile = lucky_percentile
    @percentage_hold_time = percentage_hold_time
    @hold_time_exp = hold_time_exp
    @percentage_price_drop = percentage_price_drop
    
    # @last_purchase/@last_sale indicate the timestamp and price at which a given stock
    #   was last bought/sold, nil if the given stock hasn't ever been owned.
    @last_purchase = Hash.new(Hash.new)
    @last_sale = Hash.new(Hash.new)
  end
  
  def trade(ticker, timestamp)
    ts = Time.from_timestamp(timestamp)
    
    # current price quote
    price = account.broker.quote(ticker, timestamp)
    
    # try to buy the given ticker if we aren't holding any shares
    if account.portfolio[ticker] == 0
      
      # are funds available?
      if account.cash > 0
        
        # Buy if:
        #   1. we have never purchased the given stock/ticker before, OR
        #   2. the current price is <= a percentage of the price at which we last sold this stock, OR
        #      (the price dropped since our last sale)
        #   3. the time elapsed since our last sale is >= percentage_hold_time * last hold-time duration^hold-time exponent
        #      (wait for the cool-down period to elapse)
        if(!@last_purchase.key?(ticker) || 
           price <= (1.0 - @percentage_price_drop) * @last_sale[ticker][:price] || 
           time_since_last_sale(ticker, ts) >= @percentage_hold_time * last_hold_time(ticker) ** @hold_time_exp)
          
          s = account.buy_amap(ticker, timestamp, amount_per_company)

          #puts "bought #{s} shares @ $#{price} of #{ticker} at #{timestamp}" if verbose?
          #puts "#{price} <= #{(1.0 - @percentage_price_drop) * @last_sale[ticker][:price]} = #{price <= (1.0 - @percentage_price_drop) * @last_sale[ticker][:price]}" if verbose? && @last_purchase.key?(ticker)
          #puts "#{time_since_last_sale(ticker, ts).in_days} >= #{(@percentage_hold_time * last_hold_time(ticker) ** @hold_time_exp).in_days} = #{time_since_last_sale(ticker, ts) >= @percentage_hold_time * last_hold_time(ticker) ** @hold_time_exp}" if verbose? && @last_purchase.key?(ticker)
          #puts "account: #{account.to_s(timestamp)}","-------------------------" if verbose?

          @last_purchase[ticker] = {price: price, time_stamp: ts}
        end
      end
    else                                  # try to sell our holdings of the given ticker
      last_purchase_price = @last_purchase[ticker][:price]
      # if we've made a lucky gain, sell all our shares.
      if(last_purchase_price == 0 ||
         price/last_purchase_price >= lucky_gain(current_hold_time(ticker, ts)))

        s = account.sell_all(ticker, timestamp)

        #puts "sold #{s} shares @ $#{price} of #{ticker} at #{timestamp}" if verbose?
        #puts "#{price/last_purchase_price} >= #{lucky_gain(current_hold_time(ticker, ts))} = #{price/last_purchase_price >= lucky_gain(current_hold_time(ticker, ts))}" if verbose? && last_purchase_price > 0
        #puts "account: #{account.to_s(timestamp)}","-------------------------" if verbose?

        @last_sale[ticker] = {price: price, time_stamp: ts}
      end
    end
  end
  
  def lucky_gain(hold_time_in_seconds)
    @csv_table.get(@lucky_percentile, hold_time_in_seconds, true)
  end
  
  def time_since_last_sale(ticker, time_t)
    if @last_sale[ticker][:time_stamp]
      return time_t - @last_sale[ticker][:time_stamp]
    end
    0
  end
  
  def current_hold_time(ticker, time_t)
    if @last_purchase[ticker][:time_stamp]
      return time_t - @last_purchase[ticker][:time_stamp]
    end
    0
  end
  
  def last_hold_time(ticker)
    if @last_sale[ticker][:time_stamp] && @last_purchase[ticker][:time_stamp]
      t = @last_sale[ticker][:time_stamp] - @last_purchase[ticker][:time_stamp]
      if t >= 0
        return t
      end
    end
    0
  end
  
  def to_s
    "Lucky:\n" +
    "  Lucky Percentile: #{@lucky_percentile}\n" +
    "  Percentage Hold Time: #{@percentage_hold_time}\n" +
    "  Hold Time Exponent: #{@hold_time_exp}\n" +
    "  Percentage Price Drop: #{@percentage_price_drop}\n" +
    "  Tickers: #{tickers_to_trade.join(', ')}\n" +
    "  Account: #{account.to_s}"
  end
  
  def parameter_set
    "Lucky Percentile: #{@lucky_percentile}\n" +
    "Percentage Hold Time: #{@percentage_hold_time}\n" +
    "Hold Time Exponent: #{@hold_time_exp}\n" +
    "Percentage Price Drop: #{@percentage_price_drop}"
  end
end