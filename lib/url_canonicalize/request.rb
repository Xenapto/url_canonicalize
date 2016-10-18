module URLCanonicalize
  # Make an HTTP request
  class Request
    def fetch
      puts "Fetching #{url} with #{http_method.to_s.upcase}".cyan # debug
      handle_response
    end

    private

    attr_reader :http, :http_method

    def initialize(http, http_method = :head)
      @http = http
      @http_method = http_method
    end

    def response
      @response ||= http.request request # Some URLs can throw an exception here
    end

    def request
      @request ||= request_for_method
    end

    def handle_response
      puts response.class.to_s.white # debug

      response.each_header do |k, v|
        puts "#{k}: #{v}".yellow # debug
      end

      case response
      when Net::HTTPSuccess
        look_for_canonical
      when Net::HTTPRedirection
        handle_redirection
      else
        handle_failure
      end
    end

    def look_for_canonical
      # Look in response Link header
      if response['link'] =~ /<(?<url>.+)>\s*;\s*rel="canonical"/i
        URLCanonicalize::Response::CanonicalFound.new($LAST_MATCH_INFO['url'])
      elsif http_method == :head
        self.http_method = :get
        fetch
      else
        canonical_url ? URLCanonicalize::Response::CanonicalFound.new(canonical_url, response) : response
      end
    end

    def handle_redirection
      case response
      when Net::HTTPFound, Net::HTTPMovedTemporarily, Net::HTTPTemporaryRedirect
        handle_failure
      else
        URLCanonicalize::Response::Redirect.new(response['location'])
      end
    end

    def handle_failure
    end

    def html
      @html ||= Nokogiri::HTML response.body
    end

    def canonical_url_element
      @canonical_url_element ||= html.xpath('//head/link[@rel="canonical"]').first
    end

    def canonical_url
      @canonical_url ||= canonical_url_element['href'] if @canonical_url_element.is_a?(Nokogiri::XML::Element)
    end

    def uri
      @uri ||= http.uri
    end

    def url
      @url ||= uri.to_s
    end

    def host
      @host ||= uri.host
    end

    def request_for_method
      r = base_request
      headers.each { |header_key, header_value| r[header_key] = header_value }
      r
    end

    def base_request
      check_http_method

      case http_method
      when :head
        Net::HTTP::Head.new uri
      when :get
        Net::HTTP::Get.new uri
      else
        raise URLCanonicalize::Exception::Request, "Unknown method: #{method}"
      end
    end

    def headers
      @headers ||= {
        'Accept-Language' => 'en-US,en;q=0.8',
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; WOW64) '\
                        'AppleWebKit/537.36 (KHTML, like Gecko) '\
                        'Chrome/51.0.2704.103 Safari/537.36'
      }
    end

    def http_method=(value)
      @http_method = value
      @request = nil
      @response = nil
    end

    # Some sites treat HEAD requests as suspicious activity and block the
    # requester after a few attempts. For these sites we'll use GET requests
    # only
    def check_http_method
      @http_method = :get if host =~ /(linkedin|crunchbase).com/
    end
  end
end