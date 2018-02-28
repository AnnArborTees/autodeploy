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

  def git_log_n1
    StringIO.new %{commit 0b81eca6b43ebcfab3834bb2b7b617dd1c274030
Author: NinjaButtersAATC <stefan@annarbortees.com>
Date:   Mon Feb 26 16:27:03 2018 -0500

    (HOTFIX) Fixed how dates were being sent to production.
}
  end

  extend self
end
