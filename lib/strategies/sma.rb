require '../simulator.rb'

# NEEDS TO BE UPDATED TO TIMESTAMP BASED STRATEGY

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
