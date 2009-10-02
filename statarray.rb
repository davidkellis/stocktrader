module Math
	def Math::float_equal(a,b)
		c = a-b
		c *= -1.0 if c < 0
		c < 0.000000001	# TODO: how should we pick epsilon?
	end
end

class StatArray < Array
	alias :count size

	def sum
		inject(0) { |sum, x| sum + x }
	end

	def mean
		return 0.0 if self.size == 0
		sum.to_f / self.size
	end
	alias :arithmetic_mean :mean
	
	def median
		return 0 if self.size == 0
		tmp = sort
		mid = tmp.size / 2
		if (tmp.size % 2) == 0
			(tmp[mid-1] + tmp[mid]).to_f / 2
		else
			tmp[mid]
		end
	end
	
	# The sum of the squared deviations from the mean.
	def summed_sqdevs
		return 0 if count < 2
		m = mean
		StatArray.new(map { |x| (x - m) ** 2 }).sum
	end
	
	# Variance of the sample.
	def variance
		# Variance of 0 or 1 elements is 0.0
		return 0.0 if count < 2
		summed_sqdevs / (count - 1)
	end
	
	# Variance of a population.
	def pvariance
		# Variance of 0 or 1 elements is 0.0
		return 0.0 if count < 2
		summed_sqdevs / count
	end
	
	# Standard deviation of a sample.
	def stddev
		Math::sqrt(variance)
	end

	# Standard deviation of a population.
	def pstddev
		Math::sqrt(pvariance)
	end
	
	# Calculates the standard error of this sample.
	def stderr
		return 0.0 if count < 2
		stddev/Math::sqrt(size)
	end
	
	# Returns the confidence interval for this sample as [lower,upper].
	# doc can be 90, 95, 99 or 999, defaulting to 95.
	def ci(doc = 95)
		limit = climit(doc)
		[mean-limit,mean+limit]
	end
	
	# Returns E, the error associated with this sample for the given degree of
	# confidence.
	def climit(doc = 95)
		TTable::t(doc,count)*stderr
	end
	
	# Calculates the relative mean difference of this sample.
	# Makes use of the fact that the Gini Coefficient is half the RMD.
	def relative_mean_difference
		return 0.0 if Math::float_equal(mean,0.0)
		gini_coefficient * 2
	end
	alias :rmd :relative_mean_difference
	
	# The average absolute difference of two independent values drawn from
	# the sample. Equal to the RMD * the mean.
	def mean_difference
		relative_mean_difference * mean
	end
	alias :absolute_mean_difference :mean_difference
	alias :md :mean_difference
	
	# One of the Pearson skewness measures of this sample.
	def pearson_skewness2
		3*(mean-median)/stddev
	end
	
	# The skewness of this sample.
	def skewness
		fail "Buggy"
		return 0.0 if count < 2
		m = mean
		s = inject(0) { |sum,xi| sum+(xi-m)**3 }
		s.to_f/(count*variance**(3/2))
	end
	
	# The kurtosis of this sample.
	def kurtosis
		fail "Buggy"
		return 0.0 if count < 2
		m = mean
		s = 0
		each { |xi| s += (xi-m)**4 }
		(s.to_f/((count-1)*variance**2))-3
	end
	
	# Calculates the Theil index (a statistic used to measure economic
	# inequality). http://en.wikipedia.org/wiki/Theil_index
	# TI = \sum_{i=1}^N \frac{x_i}{\sum_{j=1}^N x_j} ln \frac{x_i}{\bar{x}}
	def theil_index
		return -1 if count <= 0 or any? { |x| x < 0 }
		return 0 if count < 2 or all? { |x| Math::float_equal(x,0) }
		m = mean
		s = sum.to_f
		inject(0) do |theil,xi|
			theil + ((xi > 0) ? (Math::log(xi.to_f/m) * xi.to_f/s) : 0.0)
		end
	end
	
	# Closely related to the Theil index and easily expressible in terms of it.
	# http://en.wikipedia.org/wiki/Atkinson_index
	# AI = 1-e^{theil_index}
	def atkinson_index
		t = theil_index
		(t < 0) ? -1 : 1-Math::E**(-t)
	end
	
	# Calculates the Gini Coefficient (a measure of inequality of a distribution
	# based on the area between the Lorenz curve and the uniform curve).
	# http://en.wikipedia.org/wiki/Gini_coefficient
	# GC = \frac{1}{N} \left ( N+1-2\frac{\sum_{i=1}^N (N+1-i)y_i}{\sum_{i=1}^N y_i} \right )
	def gini_coefficient2
		return -1 if count <= 0 or any? { |x| x < 0 }
		return 0 if count < 2 or all? { |x| Math::float_equal(x,0) }
		s = 0
		sort.each_with_index { |yi,i| s += (size - i)*yi }
		(size+1-2*(s.to_f/sum.to_f)).to_f/size.to_f
	end
	
	# Slightly cleaner way of calculating the Gini Coefficient.  Any quicker?
	# GC = \frac{\sum_{i=1}^N (2i-N-1)x_i}{N^2-\bar{x}}
	def gini_coefficient
		return -1 if count <= 0 or any? { |x| x < 0 }
		return 0 if count < 2 or all? { |x| Math::float_equal(x,0) }
		s = 0
		sort.each_with_index { |li,i| s += (2*i+1-size)*li }
		s.to_f/(size**2*mean).to_f
	end
	
	# The KL-divergence from this array to that of q.
	# NB: You will possibly want to sort both P and Q before calling this
	# depending on what you're actually trying to measure.
	# http://en.wikipedia.org/wiki/Kullback-Leibler_divergence
	def kullback_leibler_divergence(q)
		fail "Buggy."
		fail "Cannot compare differently sized arrays." unless size = q.size
		kld = 0
		each_with_index { |pi,i| kld += pi*Math::log(pi.to_f/q[i].to_f) }
		kld
	end
	
	# Returns the Cumulative Density Function of this sample (normalised to a fraction of 1.0).
	def cdf(normalised = 1.0)
		s = sum.to_f
		sort.inject([0.0]) { |c,d| c << c[-1] + normalised*d.to_f/s }
	end
	
	def stats
		if size != 0
			return %Q/#{"%12.2f" % sum} #{"%12.2f" % average} #{"%12.2f" % stddev} #{"%12.2f" % min} #{"%12.2f" % max} #{"%12.2f" % median} #{"%12.2f" % size}/
		else
			return %Q/<error>/
		end
	end
	
	def to_stats
		{ :sum => sum, :mean => mean, :stddev => stddev, :min => min, :max => max, :median => median, :count => size }
	end

	def StatArray.stats_header
		%Q/#{"%12s" % "Sum"} #{"%12s" % "Avg."} #{"%12s" % "Std.dev."} #{"%12s" % "Min."} #{"%12s" % "Max."} #{"%12s" % "Median"} #{"%12s" % "Count"}/
	end
end

class TTable
	# Format of rawtvalues:
	# DegreesOfFreedom		90% 	95%		99%		99.9%
	@@rawtvalues = <<EOF
1	6.31	12.71	63.66	636.62
2	2.92	4.30	9.93	31.60
3	2.35	3.18	5.84	12.92
4	2.13	2.78	4.60	8.61
5	2.02	2.57	4.03	6.87
6	1.94	2.45	3.71	5.96
7	1.89	2.37	3.50	5.41
8	1.86	2.31	3.36	5.04
9	1.83	2.26	3.25	4.78
10	1.81	2.23	3.17	4.59
11	1.80	2.20	3.11	4.44
12	1.78	2.18	3.06	4.32
13	1.77	2.16	3.01	4.22
14	1.76	2.14	2.98	4.14
15	1.75	2.13	2.95	4.07
16	1.75	2.12	2.92	4.02
17	1.74	2.11	2.90	3.97
18	1.73	2.10	2.88	3.92
19	1.73	2.09	2.86	3.88
20	1.72	2.09	2.85	3.85
21	1.72	2.08	2.83	3.82
22	1.72	2.07	2.82	3.79
23	1.71	2.07	2.82	3.77
24	1.71	2.06	2.80	3.75
25	1.71	2.06	2.79	3.73
26	1.71	2.06	2.78	3.71
27	1.70	2.05	2.77	3.69
28	1.70	2.05	2.76	3.67
29	1.70	2.05	2.76	3.66
30	1.64	1.96	2.58	3.29
EOF
	@@tvalues = nil

	def TTable::parseTValues
		@@tvalues = Array.new
		@@rawtvalues.split(/\n/).each do |row|
			@@tvalues << row.split(/\s+/).map { |i| i.to_f }
		end
	end
	
	def TTable.t(dc,samples = 31)
		fail ArgumentError.new("Need at least 2 samples to find a t-value.") if samples < 2
		samples = 31 if samples > 31
		case dc
			when 90
				dci = 1
			when 95
				dci = 2
			when 99
				dci = 3
			when 999
				dci = 4
			else
				fail ArgumentError.new("Cannot calculate t-value for #{dc}% degree of confidence.")
		end
		TTable::parseTValues unless @@tvalues
		@@tvalues[samples-1-1][dci]
	end

	def TTable.t90(samples = 31)
		TTable::t(90,samples)
	end
	
	def TTable.t95(samples = 31)
		TTable::t(95,samples)
	end
	
	def TTable.t99(samples = 31)
		TTable::t(99,samples)
	end
	
	def TTable.t999(samples = 31)
		TTable::t(999,samples)
	end
end

class Array
	def to_statarray
		StatArray.new(self)
	end
end
