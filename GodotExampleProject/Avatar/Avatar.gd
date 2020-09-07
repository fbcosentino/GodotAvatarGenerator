##
# Generates a user profile avatar automatically based on e-mail address
# Also allows loading the from the Gravatar service (www.gravatar.com)
# Caches locally in user:// to avoid unnecessary processing/network traffic
#
# Author:
#   Fernando Cosentino
#   github.com/fbcosentino/GodotAvatarGenerator

extends Node

signal avatar_generated(status)
signal avatar_ready

export(String) var FileLocation = "user://avatars"
export(int) var NumberOfHeads = 8
export(int) var NumberOfFaces = 8

var texture = ImageTexture.new()
var status = STATUS.NoAvatar

var gravatar_http_request = HTTPRequest.new()
var gravatar_http_hash = ""

enum STATUS {
	NoAvatar,
	Internal,
	Gravatar,
	Cache
}

var this_path = get_script().get_path().get_base_dir()

func _ready():
	# HTTPRequest will only process if it is in the scene tree
	add_child(gravatar_http_request)
	# Connect the completion callback
	gravatar_http_request.connect("request_completed", self, "_http_request_completed")
	
	# Check if FileLocation exists
	var dir = Directory.new()
	if not dir.dir_exists(FileLocation):
		dir.make_dir(FileLocation)
	
	# Attempt to load from cache
	# startup loading does not fire a signal, just makes sure texture and
	# status are available with proper values
	var image = Image.new()
	var error = image.load(FileLocation)
	if error != OK:
		status = STATUS.NoAvatar
	else:
		status = STATUS.Cache
		texture.create_from_image(image)
		

# Main function to generate, download or load the avatar based on a 
# person's email address (email is hashed). Priority is to use a cached
# file. If not found, attempts to download a gravatar. If fails, relies
# on internally generated avatar.
#
# @param email_address The e-mail address to use (will be hashed)
# @param size Default image size (square size x size)
# @param use_gravatar If set to false, skip gravatar attempt and go directly
#     to internally generated avatar instead. Otherwise this argument is the
#     default action for when the gravatar is not found, as a string:
#     "404" or "" (default) - If no gravatar found, uses internally generated
#     "mp" - (mystery-person) a simple, cartoon-style silhouetted outline of a person (does not vary by email hash)
#     "identicon" - a geometric pattern based on an email hash
#     "monsterid" - a generated 'monster' with different colors, faces, etc
#     "wavatar" - generated faces with differing features and backgrounds
#     "retro" - awesome generated, 8-bit arcade-style pixelated faces
#     "robohash" - a generated robot with different colors, faces, etc
#     "blank" - a transparent PNG image
# @param use_cache If true, loads cache instead of generating a new one
func get_avatar(email_address, size, use_gravatar = "404", use_cache = true):
	
	# Attempt to load cached (if using)
	if use_cache:
		recover_avatar(email_address, size)
		yield(self, "avatar_generated")
		
		# If successful, we can stop here
		if status == STATUS.Cache:
			emit_signal("avatar_ready")
			return status
		
	# Otherwise, next is gravatar (if using)
	if use_gravatar:
		if use_gravatar == "":
			use_gravatar = "404"

		# This method uses 404 to detect gravatar absence
		request_gravatar(email_address, size, use_gravatar)
		yield(self, "avatar_generated")
		
		# If successful, we can stop here
		if status == STATUS.Gravatar:
			emit_signal("avatar_ready")
			return status
		
	# Finally, internally generated avatar
	generate_avatar(email_address, size)
	yield(self, "avatar_generated")
	
	# Now we just return the status since we have nothing left to do
	emit_signal("avatar_ready")
	return status
	

# Generates an internal avatar based on the md5 hash of a person's email
# using image files from res:// in a given location
#
# @param email_address The e-mail address to use (will be hashed)
# @param size Default image size (square size x size)
func generate_avatar(email_address, size = 80):
	var email_hash = email_address.md5_text()
	# email_hash has 32 hex characters, representing 16 bytes
	# get first 6 chars for background (and remove them)
	var bg_hash = email_hash.left(6)
	var email_hash_remain = email_hash.substr(6) # now email_hash_remain has 10 bytes
	# use next 2 chars for head (and remove them)
	var head_hash = email_hash_remain.left(2)
	email_hash_remain = email_hash_remain.substr(2) # now email_hash_remain has 8 bytes
	# use next 6 chars for head color (and remove them)
	var bg_head_hash = email_hash_remain.left(6)
	email_hash_remain = email_hash_remain.substr(6) # now email_hash_remain has 2 bytes
	# use next 2 chars for face (and remove them)
	var face_hash = email_hash_remain.left(2)
	# And we are done
	
	var bg_color = Color(bg_hash)
	var bg_head_color = Color(bg_head_hash)
	var head_id = ("0x"+head_hash).hex_to_int()
	var face_id = ("0x"+face_hash).hex_to_int()
		
	# Make background
	var image = Image.new()
	image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(bg_color)
	
	# Paste head
	var head_file = str(head_id % NumberOfHeads).pad_zeros(4)
	var head_image = Image.new()
	head_image.load(this_path+'/Defaults/Heads/'+head_file+'.png')
	head_image.resize(size, size)
	image.blend_rect(head_image, Rect2(0, 0, size, size), Vector2(0,0))
	
	# Paste face
	var face_file = str(face_id % NumberOfFaces).pad_zeros(4)
	var face_image = Image.new()
	face_image.load(this_path+'/Defaults/Faces/'+face_file+'.png')
	face_image.resize(size, size)
	image.blend_rect(face_image, Rect2(0, 0, size, size), Vector2(0,0))
	
	
	# Cache and make texture
	image.save_png(FileLocation+'/'+email_hash+'.png')
	texture.create_from_image(image)
	
	# Wait an idle frame to be consisten with asynchronous logic
	yield(get_tree(), "idle_frame")
	
	# Emit successful signal
	status = STATUS.Internal
	emit_signal("avatar_generated", status)
	
	

# Requests a gravatar image, and emits signal with status STATUS.Gravatar
# when finished loading (or STATUS.NoAvatar if not found and default = "404")
#
# @param email_address The e-mail address to use (will be hashed)
# @param size Default image size (square size x size)
# @param default Option in case the image is not found, possible options are:
#     404 - Service returns 404 error, signal will be emitted with status STATUS.NoAvatar
#     mp - (mystery-person) a simple, cartoon-style silhouetted outline of a person (does not vary by email hash)
#     identicon - a geometric pattern based on an email hash
#     monsterid - a generated 'monster' with different colors, faces, etc
#     wavatar - generated faces with differing features and backgrounds
#     retro - awesome generated, 8-bit arcade-style pixelated faces
#     robohash - a generated robot with different colors, faces, etc
#     blank - a transparent PNG image
func request_gravatar(email_address, size = 80, default = "404"):
	var email_hash = email_address.md5_text()
	gravatar_http_hash = email_hash
	var error = gravatar_http_request.request("http://gravatar.com/avatar/"+email_hash+".jpg?s="+str(size)+"&d="+str(default))
	if error != OK:
		print("gravatar error: %d" % error)
		return false
	else:
		return true

# Called when the HTTP request is completed.
func _http_request_completed(result, response_code, headers, body):
	# If response is 404, this e-mail doesn't have a gravatar
	if response_code == 404:
		status = STATUS.NoAvatar
		emit_signal("avatar_generated", status)
		return false
	
	# Get the content type
	var content_type = _get_content_type(headers)
	
	# Load the received data into an Image object, using the right method	
	var image = Image.new()
	var error
	if content_type == 'image/png':
		error = image.load_png_from_buffer(body)
	else:
		error = image.load_jpg_from_buffer(body)
	# If result is not valid image, emit NoAvatar
	if error != OK:
		status = STATUS.NoAvatar
		emit_signal("avatar_generated", status)
		return false
	
	# Otherwise, cache image and make texture
	image.save_png(FileLocation+'/'+gravatar_http_hash+'.png')
	texture.create_from_image(image)
	# Emit successful signal
	status = STATUS.Gravatar
	emit_signal("avatar_generated", status)


# Reads a cached avatar based on the md5 hash of a given email 
func recover_avatar(email_address, size):
	var email_hash = email_address.md5_text()
	var file_path = FileLocation+'/'+email_hash+'.png'
	
	var f = File.new()
	if f.file_exists(file_path):
		var image = Image.new()
		var error = image.load(file_path)
		
		# If result is not valid image, emit NoAvatar
		if error != OK:
			status = STATUS.NoAvatar
			emit_signal("avatar_generated", status)
			return false
			
		# Otherwise, cache image and make texture
		image.resize(size, size)
		texture.create_from_image(image)
		
		# Wait an idle frame to be consisten with asynchronous logic
		yield(get_tree(), "idle_frame")
		
		# Emit successful signal
		status = STATUS.Cache
		emit_signal("avatar_generated", status)

	else:
		# Wait an idle frame to be consisten with asynchronous logic
		yield(get_tree(), "idle_frame")

		status = STATUS.NoAvatar
		emit_signal("avatar_generated", status)
		return false

# Traverse headers and returns content type if found
func _get_content_type(headers):
	var search_field = "Content-Type: "
	for header in headers:
		if header.begins_with(search_field):
			return header.substr(search_field.length())
	return null
