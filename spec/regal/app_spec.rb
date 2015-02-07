require 'spec_helper'

module Regal
  describe App do
    include Rack::Test::Methods

    context 'a basic app' do
      let :app do
        a = App.create do
          get do
            'root'
          end

          route 'hello' do
            get do
              'hello'
            end

            route 'world' do
              get do
                'hello world'
              end
            end
          end
        end
        a.new
      end

      it 'routes a request' do
        get '/hello'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello')
      end

      it 'routes a request to the root' do
        get '/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('root')
      end

      it 'routes a request with more than one path component' do
        get '/hello/world'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello world')
      end

      it 'responds with 404 when the path does not match any route' do
        get '/hello/fnord'
        expect(last_response.status).to eq(404)
      end

      it 'responds with 405 when the path matches a route but there is no handler for the HTTP method' do
        delete '/hello/world'
        expect(last_response.status).to eq(405)
      end
    end

    context 'a simple interactive app' do
      let :app do
        a = App.create do
          route 'echo' do
            get do |request|
              request.parameters['s']
            end

            post do |request|
              request.body.read
            end
          end

          route 'international-hello' do
            get do |request|
              case request.headers['Accept-Language']
              when 'sv_SE'
                'hej'
              when 'fr_FR'
                'bonjour'
              else
                '?'
              end
            end
          end
        end
        a.new
      end

      it 'can access the query parameters' do
        get '/echo?s=hallo'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hallo')
      end

      it 'can access the request headers' do
        get '/international-hello', nil, {'HTTP_ACCEPT_LANGUAGE' => 'sv_SE'}
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hej')
        get '/international-hello', nil, {'HTTP_ACCEPT_LANGUAGE' => 'fr_FR'}
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('bonjour')
      end

      it 'can access the request body' do
        post '/echo', 'blobblobblob'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('blobblobblob')
      end
    end

    context 'an app that does more than just respond with a body' do
      let :app do
        a = App.create do
          route 'redirect' do
            get do |_, response|
              response.status = 307
              response.headers['Location'] = 'somewhere/else'
            end
          end
        end
        a.new
      end

      it 'can change the response code' do
        get '/redirect'
        expect(last_response.status).to eq(307)
      end

      it 'can set response headers' do
        get '/redirect'
        expect(last_response.headers).to include('Location' => 'somewhere/else')
      end
    end

    context 'an app doing work before route handlers' do
      let :app do
        a = App.create do
          before do |request|
            request.attributes[:some_key] = [1]
          end

          get do |request|
            request.attributes[:some_key].join(',')
          end

          route 'one-before' do
            before do |request|
              request.attributes[:some_key] << 2
            end

            get do |request|
              request.attributes[:some_key].join(',')
            end
          end

          route 'two-before' do
            before do |request|
              request.attributes[:some_key] << 2
            end

            before do |request|
              request.attributes[:some_key] << 3
            end

            get do |request|
              request.attributes[:some_key].join(',')
            end

            route 'another-before' do
              before do |request|
                request.attributes[:some_key] << 4
              end

              get do |request|
                request.attributes[:some_key].join(',')
              end
            end
          end
        end
        a.new
      end

      it 'calls the before block before the request handler' do
        get '/'
        expect(last_response.body).to eq('1')
      end

      it 'calls the before blocks of all routes before the request handler' do
        get '/one-before'
        expect(last_response.body).to eq('1,2')
      end

      it 'calls all before blocks of a route before the request handler' do
        get '/two-before'
        expect(last_response.body).to eq('1,2,3')
        get '/two-before/another-before'
        expect(last_response.body).to eq('1,2,3,4')
      end
    end

    context 'an app that has capturing routes' do
      let :app do
        a = App.create do
          route 'foo' do
            route :bar do
              get do
                'whatever'
              end

              route 'echo' do
                get do |request|
                  request.parameters[:bar]
                end
              end
            end

            route 'bar' do
              get do
                'bar'
              end
            end
          end
        end
        a.new
      end

      it 'matches anything for the capture route' do
        get '/foo/something'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('whatever')
        get '/foo/something-else'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('whatever')
      end

      it 'picks static routes first' do
        get '/foo/bar'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('bar')
      end

      it 'captures the path component as a parameter using a symbol as key' do
        get '/foo/zzz/echo'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('zzz')
        get '/foo/q/echo'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('q')
      end
    end

    context 'an app that mounts another app' do
      GoodbyeApp = App.create do
        route 'goodbye' do
          get do
            'goodbye'
          end
        end
      end

      HelloApp = App.create do
        route 'hello' do
          get do
            'hello'
          end

          route 'you' do
            route 'say' do
              mount GoodbyeApp
            end
          end
        end
      end

      let :app do
        a = App.create do
          route 'i' do
            route 'say' do
              mount HelloApp
              mount GoodbyeApp
            end
          end

          route 'oh' do
            mount HelloApp
          end
        end
        a.new
      end

      it 'routes a request into the other app' do
        get '/i/say/hello'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello')
      end

      it 'can mount multiple apps' do
        get '/i/say/goodbye'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('goodbye')
      end

      it 'routes a request into apps that mount yet more apps' do
        get '/i/say/hello/you/say/goodbye'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('goodbye')
      end

      it 'can mount the same app multiple times' do
        get '/oh/hello'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello')
      end
    end
  end
end
