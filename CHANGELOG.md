# Changelog

## 0.5.0 (unreleased)
  * Use Memcached#exist if available (performance improvement ~25%)
  * Correctly escape bad characters and too long keys
  * Add benchmarks
  * Remove the use of ActiveSupport::Entry which was a performance bottleneck #3

## 0.4.0
  * Optimize read_multi to only make one call to memecached server
  * Update test suite to reflect Rails' one
  * Add session store tests