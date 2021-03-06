# encoding: utf-8
module Prismic
  class API
    attr_reader :json, :access_token
    attr_accessor :refs, :bookmarks, :forms, :master, :tags, :types, :oauth

    def initialize(json, access_token=nil)
      @json = json
      @access_token = access_token
      yield self if block_given?
      self.master = refs.values && refs.values.map { |ref| ref if ref.master? }.compact.first
      raise BadPrismicResponseError, "No master Ref found" unless master
    end

    def bookmark(name)
      bookmarks[name]
    end

    def ref(name)
      refs[name.downcase]
    end

    def master_ref
      ref('master')
    end

    def form(name)
      forms[name]
    end

    def create_search_form(name, data={}, ref={})
      form = self.form(name)
      form and form.create_search_form(data, ref)
    end

    def as_json
      @json
    end

    def self.get(url, access_token=nil)
      uri = URI(access_token ? "#{url}?access_token=#{access_token}" : url)
      http = Net::HTTP.new(uri.host)
      req = Net::HTTP::Get.new(uri.path, 'Accept' => 'application/json')
      res = http.request(req)

      if res.code == '200'
        res
      else
        raise PrismicWSConnectionError, res
      end
    end

    def self.start(url, access_token=nil)
      resp = get(url, access_token)
      json = JSON.load(resp.body)
      parse_api_response(json, access_token)
    end

    def self.parse_api_response(data, access_token=nil)
      data_forms = data['forms'] || []
      data_refs = data.fetch('refs'){ raise BadPrismicResponseError, "No refs given" }
      new(data, access_token) {|api|
        api.bookmarks = data['bookmarks']
        api.forms = Hash[data_forms.map { |k, form|
          [k, Form.new(
            api,
            form['name'],
            Hash[form['fields'].map { |k2, field|
              [k2, Field.new(field['type'], field['default'], k2 == 'q')]
            }],
            form['method'],
            form['rel'],
            form['enctype'],
            form['action'],
          )]
        }]
        api.refs = Hash[data_refs.map { |ref|
          scheduled_at = ref['scheduledAt']
          [ref['label'].downcase, Ref.new(ref['ref'], ref['label'], ref['isMasterRef'], scheduled_at && Time.at(scheduled_at / 1000.0))]
        }]
        api.tags = data['tags']
        api.types = data['types']
        api.oauth = OAuth.new(data['oauth_initiate'], data['oauth_token'])
      }
    end

    def oauth_initiate_url(opts)
      oauth.initiate + "?" + {
        "client_id" => opts.fetch(:client_id),
        "redirect_uri" => opts.fetch(:redirect_uri),
        "scope" => opts.fetch(:scope),
      }.map{|kv| kv.map{|e| CGI.escape(e) }.join("=") }.join("&")
    end

    def oauth_check_token(params)
      uri = URI(oauth.token)
      res = Net::HTTP.post_form(uri, params)
      if res.code == '200'
        begin
          JSON.parse(res.body)['access_token']
        rescue Exception => e
          raise PrismicWSConnectionError.new(res, e)
        end
      else
        raise PrismicWSConnectionError, res
      end
    end

    private

    class BadPrismicResponseError < Error ; end

    class PrismicWSConnectionError < Error
      def initialize(resp, cause=nil)
        super("Can't connect to Prismic's API: #{resp.code} #{resp.message}", cause)
      end
    end

    class OAuth
      attr_reader :initiate, :token
      def initialize(initiate, token)
        @initiate = initiate
        @token = token
      end
    end
  end
end
