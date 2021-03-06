module OutputStub
  def git_show
    StringIO.new %{commit cabc994a5cf74f85f86b33a3149a8cf48464aadc
Author: Ricky Winowiecki <ricky@annarbortshirtcompany.com>
Date:   Wed Feb 28 09:48:33 2018 -0500

    (2381) Data included in API needed by Katherine

diff --git a/app/controllers/api/stores_controller.rb b/app/controllers/api/stores_controller.rb
index 374a794..111dde9 100644
--- a/app/controllers/api/stores_controller.rb
+++ b/app/controllers/api/stores_controller.rb
@@ -35,7 +35,7 @@ class Api::StoresController < ActionController::Base
   private
 
   def render_store_json
-    render json: @store
+    render json: @store.to_json(include: :store_collections, methods: :header_image_url)
   end
 
   def allow_any_origin
diff --git a/app/models/store.rb b/app/models/store.rb
index 0595763..b41d4cb 100644
--- a/app/models/store.rb
+++ b/app/models/store.rb
@@ -59,6 +59,14 @@ class Store < ApplicationRecord
     account.name rescue "No Account"
   end
 
+  def header_image_url
+    header_image.url
+  end
+
+  def favicon_url
+    favicon.url
+  end
+
   def initialize_colors_and_fonts
     return if self.persisted?
     self.header_font_family = '"Helvetica Neue", Helvetica, Arial, sans-serif' if self.header_font_family.blank?
}
  end

  def git_status
    StringIO.new %{On branch master
Your branch is up-to-date with 'origin/master'.

nothing to commit, working tree clean
}
  end

  def git_status_detached
    StringIO.new %{HEAD detached at 3bfcd53
nothing to commit, working tree clean
}
  end

  def git_log_n1
    StringIO.new %{commit 0b81eca6b43ebcfab3834bb2b7b617dd1c274030
Author: NinjaButtersAATC <stefan@annarbortees.com>
Date:   Mon Feb 26 16:27:03 2018 -0500

    (HOTFIX) Fixed how dates were being sent to production.
}
  end

  def git_branch_a
    StringIO.new %{  email-on-failure
* master
  multi-rspec
  random-failures-workaround
  rework
  remotes/origin/email-on-failure
  remotes/origin/master
  remotes/origin/multi-rspec
  remotes/origin/random-failures-workaround
  remotes/origin/rework
}
  end

  def git_checkout
    StringIO.new %{Switched to a new branch 'story-2222-stefan'
Branch story-2222-stefan set up to track remote branch story-2222-stefan from origin.
}
  end

  def git_checkout_commit
    StringIO.new %{Note: checking out '3bfcd53e18606c6b933ed94221428b4206039431'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by performing another checkout.

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -b with the checkout command again. Example:

  git checkout -b <new-branch-name>

HEAD is now at 3bfcd53... update production ip
}
  end

  extend self
end
