require_relative 'app'
require 'open3'

class ShopifyApp < App
  def setup_commands
    [
      %w(yarn install)
    ]
  end

  def run_tests!(run)
    ENV['CI'] = 'true'
    success = run.record('yarn', 'test')
    ENV.delete 'CI'

    success
  end

  def deploy_commands
    [
      %w(yarn build),
      %w(scp -r build/* ubuntu@52.5.26.219:~/ReactApps/aatc-ssa-shopify)
    ]
  end
end
