//
//  GStreamerBackend.c
//  GStreamerSwiftUIDemo
//
//  Created by Raktim Bora on 19.06.23.
//

#include<unistd.h>
#include "GStreamerBackend.h"
# include "gst_ios_init.h"
#include <UIKit/UIKit.h>

#include <GStreamer/gst/gst.h>
#include <GStreamer/gst/video/video.h>
#import "GStreamerSwiftUIDemo-Swift.h"

#import <Foundation/Foundation.h>

GST_DEBUG_CATEGORY_STATIC (debug_category);
#define GST_CAT_DEFAULT debug_category

@interface GStreamerBackend()
-(void)setUIMessage:(gchar*) message;
-(void)run_app_pipeline;
-(void)check_initialization_complete;
@end

@implementation GStreamerBackend {
    id ui_delegate;        /* Class that we use to interact with the user interface */
    GstElement *pipeline;  /* The running pipeline */
    GstElement *video_sink;/* The video sink element which receives XOverlay commands */
    GMainContext *context; /* GLib context used to run the main loop */
    GMainLoop *main_loop;  /* GLib main loop */
    gboolean initialized;  /* To avoid informing the UI multiple times about the initialization */
    GstBus *bus;
    UIView *ui_video_view; /* UIView that holds the video */
    GstMessage* eos_msg;
}

/*
 * Interface methods
 */

-(id) init:(id) uiDelegate videoView:(UIView *)video_view
{
    if (self = [super init])
    {
        self->ui_delegate = uiDelegate;
        self->ui_video_view = video_view;

        GST_DEBUG_CATEGORY_INIT (debug_category, "GStreamerSwiftUIDemo", 0, "GStreamerSwiftUIDemo-Backend");
        gst_debug_set_threshold_for_name("GStreamerSwiftUIDemo", GST_LEVEL_TRACE);
    }

    return self;
}

-(void) run_app_pipeline_threaded
{
    [self run_app_pipeline];
    return;
}



-(void) play
{
    if(gst_element_set_state(pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        [self setUIMessage:"Failed to set pipeline to playing"];
    }
}


-(void) pause
{
    if(gst_element_set_state(pipeline, GST_STATE_PAUSED) == GST_STATE_CHANGE_FAILURE) {
        [self setUIMessage:"Failed to set pipeline to paused"];
    }
}

-(void) destroy
{
    if(gst_element_set_state(pipeline, GST_STATE_PAUSED) == GST_STATE_CHANGE_FAILURE) {
        [self setUIMessage:"Failed to set pipeline to READY"];
    }
    eos_msg = gst_message_new_eos(GST_OBJECT(pipeline));
    gst_element_post_message (pipeline, eos_msg);
}


/* Change the message on the UI through the UI delegate */
-(void)setUIMessage:(gchar*) message
{
    NSString *messagString = [NSString stringWithUTF8String:message];
    if(ui_delegate && [ui_delegate respondsToSelector:@selector(gstreamerSetUIMessageWithMessageWithMessage:)])
    {
        [ui_delegate gstreamerSetUIMessageWithMessageWithMessage:messagString];
    }
}

static void eos_cb(GstBus *bus, GstMessage *msg, GStreamerBackend *self){
    printf("\neos called\n");
    gst_element_set_state (self->pipeline, GST_STATE_NULL);
    g_main_loop_quit(self->main_loop);
}

/* Retrieve errors from the bus and show them on the UI */
static void error_cb (GstBus *bus, GstMessage *msg, GStreamerBackend *self)
{
    GError *err;
    gchar *debug_info;
    gchar *message_string;

    gst_message_parse_error (msg, &err, &debug_info);
    message_string = g_strdup_printf ("Error received from element %s: %s", GST_OBJECT_NAME (msg->src), err->message);
    printf("Some error occured in from element %s: %s", GST_OBJECT_NAME (msg->src), err->message);
    g_clear_error (&err);
    g_free (debug_info);
    [self setUIMessage:message_string];
    g_free (message_string);
    gst_element_set_state (self->pipeline, GST_STATE_NULL);
}

/* Notify UI about pipeline state changes */
static void state_changed_cb (GstBus *bus, GstMessage *msg, GStreamerBackend *self)
{
    GstState old_state, new_state, pending_state;
    gst_message_parse_state_changed (msg, &old_state, &new_state, &pending_state);
    /* Only pay attention to messages coming from the pipeline, not its children */
    if (GST_MESSAGE_SRC (msg) == GST_OBJECT (self->pipeline)) {
        gchar *message = g_strdup_printf("State changed from %s to %s", gst_element_state_get_name(old_state), gst_element_state_get_name(new_state));
        [self setUIMessage:message];
        g_free (message);
    }
}

/* Check if all conditions are met to report GStreamer as initialized.
 * These conditions will change depending on the application */
-(void) check_initialization_complete
{
    if (!initialized && main_loop) {
        GST_DEBUG ("Initialization complete, notifying application.");
        if (ui_delegate && [ui_delegate respondsToSelector:@selector(gStreamerInitialized)])
        {
            [ui_delegate gStreamerInitialized];
        }
        initialized = TRUE;
    }
}

/* Main method */
-(void) run_app_pipeline
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];

    NSString* caBundleCertPath = [[NSBundle mainBundle] pathForResource:@"cert" ofType:@"pem" inDirectory:@"certs"];

    if (caBundleCertPath == nil) {
      [self setUIMessage:"Failed to find 'certs/cert.pem' file."];
      return;
    }

    if (setenv("AWS_KVS_CACERT_PATH", [caBundleCertPath fileSystemRepresentation], 1) != 0) {
      [self setUIMessage:"Failed to set 'AWS_KVS_CACERT_PATH' environment variable."];
      return;
    }

    NSString *kvsLogConfigurationPath = [documentsDirectory stringByAppendingPathComponent:@"aws-kvs-log.cfg"] ?: @"";

    if (kvsLogConfigurationPath.length != 0 && fileManager != nil) { // && ![fileManager fileExistsAtPath:kvsLogConfigurationPath]) {
      NSString* kvsLogConfigurationBundlePath = [[NSBundle mainBundle] pathForResource:@"aws-kvs-log" ofType:@"cfg"];

      if (kvsLogConfigurationBundlePath != nil) {
        [fileManager removeItemAtPath: kvsLogConfigurationPath error:nil];
        [fileManager copyItemAtPath:kvsLogConfigurationBundlePath toPath:kvsLogConfigurationPath error:nil];
      }
    }

    NSString *kvsLogFolder = [documentsDirectory stringByAppendingPathComponent:@"logs"] ?: @"";

    if (kvsLogFolder.length != 0 && fileManager != nil) {
      [fileManager createDirectoryAtPath:kvsLogFolder withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSString *videoFolder = [documentsDirectory stringByAppendingPathComponent:@"video/hls"] ?: @"";
  
    if (videoFolder.length != 0 && fileManager != nil) {
      [fileManager createDirectoryAtPath:videoFolder withIntermediateDirectories:YES attributes:nil error:nil];
    }
  
    setenv("AWS_KVS_LOGS_FOLDER", [kvsLogFolder fileSystemRepresentation], 1);

    GSource *bus_source;
    GError *error = NULL;

    GST_DEBUG ("Creating pipeline");

    /* Create our own GLib Main Context and make it the default one */
    context = g_main_context_new ();
    g_main_context_push_thread_default(context);
  
    gst_debug_set_default_threshold(GST_LEVEL_DEBUG);

    char pipelineStr[2048];

    const char* clockoverlayTimeFormat = "\"%a %B %d, %Y %I:%M:%S %p\"";
    const char* awsRegion = "REPLACE_ME";
    const char* awsAccessKey = "REPLACE_ME";
    const char* awsSecretKey = "REPLACE_ME";
    const char* kvsLogConfigurationPathCStr = (kvsLogConfigurationPath != nil) ? [kvsLogConfigurationPath fileSystemRepresentation] : "";
    const char* videoFolderCStr = [videoFolder fileSystemRepresentation];

    snprintf(pipelineStr,
             sizeof(pipelineStr),
             "avfvideosrc "
             " ! queue "
             " ! video/x-raw, width=1280, height=720, framerate=30/1 "
             " ! videoconvert "
             " ! vtenc_h264 "
             " ! queue "
             " ! h264parse "
             " ! hlssink2 name=local-hls-sink max-files=4294967295 playlist-length=0 target-duration=5 location=%s/segment-%s.ts playlist-location=%s/playlist.m3u8 "
             " audiotstsrc is-live=true wave=0 freq=440.0 volume=0.5 "
             " ! queue "
             " ! audioconvert "
             " ! avenc_aac "
             " ! queue "
             " ! aacparse "
             " ! local-hls-sink.audio",
             videoFolderCStr,
             "%5d",
             videoFolderCStr);

      bool showLocalVideo = false;

      pipeline = gst_parse_launch(pipelineStr, &error);

      if (error && !GST_IS_ELEMENT(pipeline)) {
          gchar *message = g_strdup_printf("Unable to build pipeline: %s", error->message);
          g_clear_error (&error);
          [self setUIMessage:message];
          g_free (message);
          return;
      }

      gst_element_set_state(pipeline, GST_STATE_READY);

  //    GstElement *base_sink = gst_bin_get_by_interface(GST_BIN(pipeline), GST_TYPE_BASE_SINK);
  //
      if (showLocalVideo) {
        video_sink = gst_bin_get_by_interface(GST_BIN(pipeline), GST_TYPE_VIDEO_OVERLAY);
        if (video_sink != nil) {
          gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY(video_sink), (guintptr) (id) ui_video_view);
        }
      }
  //
  //    if (base_sink == nil && video_sink == nil) {
  //      GST_ERROR ("Could not retrieve sink");
  //      return;
  //    }

      /* Signals to watch */
      bus = gst_element_get_bus (pipeline);
      bus_source = gst_bus_create_watch (bus);
      g_source_set_callback (bus_source, (GSourceFunc) gst_bus_async_signal_func, NULL, NULL);
      g_source_attach (bus_source, context);
      g_source_unref (bus_source);
      g_signal_connect (G_OBJECT (bus), "message::error", (GCallback)error_cb, (__bridge void *)self);
      g_signal_connect (G_OBJECT (bus), "message::eos", (GCallback)eos_cb, (__bridge void *)self);
      g_signal_connect (G_OBJECT (bus), "message::state-changed", (GCallback)state_changed_cb, (__bridge void *)self);
      gst_object_unref (bus);

      /* Create a GLib Main Loop and set it to run */
      GST_DEBUG ("Entering main loop...");
      printf("\nEntering main loop..\n");
      main_loop = g_main_loop_new (context, FALSE);
      //sleep(5);
      [self check_initialization_complete];
      g_main_loop_run (main_loop);
      GST_DEBUG ("Exited main loop");
      g_main_loop_unref (main_loop);
      main_loop = NULL;

      /* Free resources */
      g_main_context_pop_thread_default(context);
      g_main_context_unref (context);
      gst_element_set_state (pipeline, GST_STATE_NULL);
      gst_object_unref (pipeline);
      return;
}

@end


