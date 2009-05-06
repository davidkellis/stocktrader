# requires >= ruby 1.8.7

# intended to be mixed into the Array class
module Statistics
  # compute the average
  def mean
    return 0 if length == 0
    sequence_sum / length
  end
  
  # compute the sum of a sequence of terms
  def sequence_sum
    reduce(:+)
  end
  
  # compute the product of a sequence of terms
  def sequence_product
    reduce(:*)
  end
  
  def differences_from_mean
    avg = mean
    differences_from_mean = map { |term| term - avg }
  end
  
  # compute the sum-of-squares of a sequence of terms
  def sum_of_squares
    squares = differences_from_mean.map { |diff| diff ** 2 }
    squares.reduce(:+)
  end
  
  # compute the population variance of a sequence of terms
  def population_variance
    return 0 if length == 0
    sum_of_squares / length
  end
  
  # compute the population variance of a sequence of terms
  def sample_variance
    return 0 if length <= 1
    sum_of_squares / (length - 1)
  end

  # compute the standard deviation
  def population_std_dev
    # even though Math.sqrt doesn't operate on arbitrary precision numbers, we'll use it anyway
    Math.sqrt(population_variance)
  end

  # compute the standard deviation
  def sample_std_dev
    # even though Math.sqrt doesn't operate on arbitrary precision numbers, we'll use it anyway
    Math.sqrt(sample_variance)
  end
  
  # compute the standard error of sample mean
  def sample_std_err
    sample_std_dev / Math.sqrt(length)
  end
  
  def sample_t_statistic(null_hypothesis_mean)
    (mean - null_hypothesis_mean) / sample_std_err
  end

  def two_tailed_p_score(t, df)
    self.class.two_tailed_p_score(t, df)
  end

  def one_tailed_p_score(t, df)
    self.class.one_tailed_p_score(t, df)
  end

  module ClassMethods
    # compute the two-tailed p score given a t-statistic and degrees-of-freedom
    # Javascript implementation of this function found in the source code of:
    #   http://home.ubalt.edu/ntsbarsh/Business-stat/otherapplets/pvalues.htm#rtdist
    # I ported the JavaScript to Ruby
    # I believe this is a numerical method of computing the integral that evaluates to the area under the t distribution curve,
    #   given the t-statistic and degrees-of-freedom.
    def two_tailed_p_score(t, df)
      t = t.abs
      w = t / Math.sqrt(df)
      th = Math.atan(w)
      return (1 - th / (Math::PI / 2)) if df == 1
      sth = Math.sin(th)
      cth = Math.cos(th)
      if(df % 2 == 1)
        1 - (th + sth * cth * stat_com(cth ** 2, 2, df - 3, -1)) / (Math::PI / 2)
      else
        1 - sth * stat_com(cth ** 2, 1, df - 3, -1)
      end
    end
  
    def one_tailed_p_score(t, df)
      two_tailed_p_score(t, df) / 2.0
    end

    # This is a utility function used by two_tailed_p_score, ported from a javascript implementation found in the source code of:
    #   http://home.ubalt.edu/ntsbarsh/Business-stat/otherapplets/pvalues.htm#rtdist
    # I ported the JavaScript to Ruby
    def stat_com(q, i, j, b)
      z = zz = 1
      k = i
      while(k <= j)
        zz = zz * q * k / (k - b)
        z = z + zz
        k += 2
      end
      z
    end
  end
  
  def self.included(base)
    base.extend(ClassMethods)
  end
end


class Array
  include Statistics
end