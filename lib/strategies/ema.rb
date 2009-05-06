require '../simulator.rb'

# NEEDS TO BE UPDATED TO TIMESTAMP BASED STRATEGY

class EMAStrategy < Strategy
  # n_periods must be >= 1 day
  def initialize(account, tickers_to_trade, n_periods)
    super(account, tickers_to_trade)
    
    @n_periods = n_periods
    @smoothing_const = 2.0 / (n_periods + 1)
    @emas = Hash.new
    @price_relation_to_average = Hash.new(0)
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
