=begin
    Copyright 2010-2012 Tasos Laskos <tasos.laskos@gmail.com>

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
=end

require Arachni::Options.instance.dir['lib'] + 'module/element_db'
require Arachni::Options.instance.dir['lib'] + 'module/output'

module Arachni
module Module

#
# Trainer class
#
# Analyzes all HTTP responses looking for new auditable elements.
#
# @author   Tasos Laskos <tasos.laskos@gmail.com>
#
class Trainer

    include Output
    include ElementDB
    include Utilities

    def initialize
      @opts     = Options.instance
      @updated  = false

      @pages = []
    end

    def init_from_page( page )
        init_db_from_page( page )
        page=( page )
    end

    def page=( page )
        @page = page.deep_clone
    end

    def follow?( url )
        !@parser.skip?( url )
    end

    #
    # Passes the reponse to {#analyze} for analysis
    #
    # @param  [Typhoeus::Response]  res
    # @param  [Bool]  redir  was the response forcing a redirection?
    #
    def add_response( res, redir = false )

        @parser = Parser.new( Options.instance, res )
        return false if !@parser.text?

        @parser.url = @page.url
        begin
            url = @parser.to_absolute( res.effective_url )

            return if !follow?( url )

            analyze( res, redir )
        rescue Exception => e
            print_error( "Invalid URL, probably broken redirection. Ignoring..." )
            print_error( "URL: #{res.effective_url}" )
            print_error_backtrace( e )
            raise e
        end
    end

    #
    # Analyzes a response looking for new links, forms and cookies.
    #
    # @param   [Typhoeus::Response]  res
    # @param   [Bool]  redir    was the response a result of a redirect?
    #
    def analyze( res, redir = false )

        print_debug( 'Started for response with request ID: #' + res.request.id.to_s )

        @parser.url = @parser.to_absolute( url_sanitize( res.effective_url ) )

        train_cookies!

        # if the response body is the same as the page body and
        # no new cookies have appeared there's no reason to analyze the page
        if( res.body == @page.body && !@updated )
            print_debug( 'Page hasn\'t changed, skipping...' )
            return
        end

        train_forms!
        train_links!( res, redir )

        if @updated

            begin
                url         = res.request.url
                # prepare the page url
                @parser.url = @parser.to_absolute( url )
            rescue Exception => e
                print_error( "Invalid URL, probably broken redirection. Ignoring..." )

                begin
                    print_error( "URL: #{res.request.url}" )
                rescue
                end

                print_error_backtrace( e )
                return
            end

            @page.html = res.body.dup
            @page.response_headers    = res.headers_hash
            @page.query_vars = @parser.link_vars( @parser.url ).dup
            @page.url        = @parser.url.dup
            @page.code       = res.code
            @page.method     = res.request.method.to_s.upcase

            @page.forms      ||= []
            @page.links      ||= []
            @page.cookies    ||= []

            @pages << @page

            @updated = false
        end

        print_debug( 'Training complete.' )
    end

    def flush_pages
        pages = @pages.dup
        @pages = []
        pages
    end

    private

    def train_forms!
        return [], 0 if !@opts.audit_forms

        cforms, form_cnt = update_forms( @parser.forms )

        if ( form_cnt > 0 )
            @page.forms = cforms.flatten.map{ |elem| elem.override_instance_scope!; elem }
            @updated = true

            print_info( 'Found ' + form_cnt.to_s + ' new forms.' )
        end
    end

    def train_links!( res, redir = false )
        return [], 0  if !@opts.audit_links

        links = @parser.links.deep_clone
        if( redir )

            url = @parser.to_absolute( url_sanitize( res.effective_url ) )
            links << Arachni::Parser::Element::Link.new( url, {
                'href' => url,
                'vars' => @parser.link_vars( url )
            } )
        end

        clinks, link_cnt = update_links( links )

        if ( link_cnt > 0 )
            @page.links = clinks.flatten.map{ |elem| elem.override_instance_scope!; elem }
            @updated = true

            print_info( 'Found ' + link_cnt.to_s + ' new links.' )
        end
    end

    def train_cookies!
        ccookies, cookie_cnt = update_cookies( @parser.cookies )

        if ( cookie_cnt > 0 )
            @page.cookies = ccookies.flatten.map{ |elem| elem.override_instance_scope!; elem }
            @updated = true

            print_info( 'Found ' + cookie_cnt.to_s + ' new cookies.' )
        end
    end

    def self.info
      { :name  => 'Trainer' }
    end

end
end
end
