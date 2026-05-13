# frozen_string_literal: true

module Archaeo
  # Fetches CDX pages in parallel for faster bulk queries.
  #
  # Wraps CdxApi and uses a thread pool to fetch multiple CDX
  # result pages simultaneously, then merges results in order.
  class ParallelCdx
    DEFAULT_CONCURRENCY = 4

    def initialize(cdx_api: CdxApi.new, concurrency: DEFAULT_CONCURRENCY)
      @cdx = cdx_api
      @concurrency = [concurrency.to_i, 1].max
    end

    def snapshots(url, **options)
      pages = @cdx.num_pages(url, **options)
      return @cdx.snapshots(url, **options) if pages <= 1

      fetch_parallel(url, options, pages)
    end

    private

    def fetch_parallel(url, options, total_pages)
      queue = (0...total_pages).to_a
      results = Array.new(total_pages)
      mutex = Mutex.new

      threads = Array.new(@concurrency) do
        Thread.new do
          loop do
            page_num = mutex.synchronize { queue.shift }
            break unless page_num

            opts = options.merge(page: page_num)
            page_results = @cdx.snapshots(url, **opts).to_a
            mutex.synchronize { results[page_num] = page_results }
          end
        end
      end

      threads.each(&:join)
      results.compact.flatten
    end
  end
end
