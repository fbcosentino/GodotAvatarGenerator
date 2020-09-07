# Example project to demonstrate the Avatar generator
#
# Author:
#   Fernando Cosentino
#   github.com/fbcosentino/GodotAvatarGenerator

extends Control

# List of values for the gravatar modes used by BtnGravatar
var gravatar_modes = [
	false,
	"404",
	"mp",
	"identicon",
	"monsterid",
	"wavatar",
	"retro",
	"robohash",
	"blank"
]

onready var Avatar = get_node("Avatar")

onready var EditEmail = get_node("Panel/EditEmail")
onready var BtnGravatar = get_node("Panel/BtnGravatar")
onready var BtnCache = get_node("Panel/BtnCache")

onready var DisplayRect = get_node("Panel/Panel/DisplayRect")

var no_avatar_texture = preload("res://no_avatar.png")


func _on_BtnGenerate_pressed():
	# Email address to be hashed
	var email_address = EditEmail.text
	# Size will be a square size x size
	var size = 192
	# Get the mode string (or false to avoid checking gravatar at all)
	var use_gravatar = gravatar_modes[ BtnGravatar.selected ]
	# Should we use cache?
	var use_cache = BtnCache.pressed
	# Finally, generate the avatar
	Avatar.get_avatar(email_address, size, use_gravatar, use_cache)
	
	# Wait for the completion signal
	yield(Avatar, "avatar_ready")
	
	# check if avatar was generated
	if Avatar.status != Avatar.STATUS.NoAvatar:
		# Put the image on display
		DisplayRect.texture = Avatar.texture
	# Otherwise shows no-avatar
	else:
		DisplayRect.texture = no_avatar_texture
