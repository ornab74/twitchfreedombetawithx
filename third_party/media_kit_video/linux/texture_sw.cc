// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "include/media_kit_video/texture_sw.h"

#include <epoxy/gl.h>

struct _TextureSW {
  FlTextureGL parent_instance;
  guint32 name;
  guint32 current_width;
  guint32 current_height;
  VideoOutput* video_output;
};

G_DEFINE_TYPE(TextureSW, texture_sw, fl_texture_gl_get_type())

static void texture_sw_init(TextureSW* self) {
  self->name = 0;
  self->current_width = 1;
  self->current_height = 1;
  self->video_output = NULL;
}

static void texture_sw_dispose(GObject* object) {
  TextureSW* self = TEXTURE_SW(object);
  if (self->name != 0) {
    glDeleteTextures(1, &self->name);
    self->name = 0;
  }
  G_OBJECT_CLASS(texture_sw_parent_class)->dispose(object);
}

static void texture_sw_class_init(TextureSWClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = texture_sw_populate_texture;
  G_OBJECT_CLASS(klass)->dispose = texture_sw_dispose;
}

TextureSW* texture_sw_new(VideoOutput* video_output) {
  TextureSW* self = TEXTURE_SW(g_object_new(texture_sw_get_type(), NULL));
  self->video_output = video_output;
  return self;
}

gboolean texture_sw_populate_texture(FlTextureGL* texture,
                                     guint32* target,
                                     guint32* name,
                                     guint32* width,
                                     guint32* height,
                                     GError** error) {
  TextureSW* self = TEXTURE_SW(texture);
  VideoOutput* video_output = self->video_output;
  const guint8* pixel_buffer = NULL;
  gint64 required_width = 0;
  gint64 required_height = 0;
  const gboolean has_frame = video_output_acquire_software_frame(
      video_output, &pixel_buffer, &required_width, &required_height);

  if (self->name == 0) {
    glGenTextures(1, &self->name);
    glBindTexture(GL_TEXTURE_2D, self->name);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    const guint8 black[4] = {0, 0, 0, 255};
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, black);
  } else {
    glBindTexture(GL_TEXTURE_2D, self->name);
  }

  gboolean resized = FALSE;
  if (has_frame) {
    resized = self->current_width != (guint32)required_width ||
              self->current_height != (guint32)required_height;
    if (resized) {
      // Allocate only when dimensions change. Flutter's stock pixel-buffer
      // path calls glTexImage2D for every frame, which repeatedly reallocates
      // the CPU-backed llvmpipe texture and causes avoidable raster jank.
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, (GLsizei)required_width,
                   (GLsizei)required_height, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                   pixel_buffer);
      self->current_width = (guint32)required_width;
      self->current_height = (guint32)required_height;
    } else {
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, (GLsizei)required_width,
                      (GLsizei)required_height, GL_RGBA, GL_UNSIGNED_BYTE,
                      pixel_buffer);
    }
    video_output_release_software_frame(video_output);
  }

  glBindTexture(GL_TEXTURE_2D, 0);
  *target = GL_TEXTURE_2D;
  *name = self->name;
  *width = self->current_width;
  *height = self->current_height;

  if (resized) video_output_notify_texture_update(video_output);
  return TRUE;
}
