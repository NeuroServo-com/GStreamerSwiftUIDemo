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

    setenv("AWS_KVS_LOGS_FOLDER", [kvsLogFolder fileSystemRepresentation], 1);

    GSource *bus_source;
    GError *error = NULL;

    GST_DEBUG ("Creating pipeline");

    /* Create our own GLib Main Context and make it the default one */
    context = g_main_context_new ();
    g_main_context_push_thread_default(context);

    char pipelineStr[1024];

    const char* awsRegion = "REPLACE_ME";
    const char* awsAccessKey = "REPLACE_ME";
    const char* awsSecretKey = "REPLACE_ME";
    const char* kvsLogConfigurationPathCStr = (kvsLogConfigurationPath != nil) ? [kvsLogConfigurationPath fileSystemRepresentation] : "";

//    snprintf(pipelineStr, sizeof(pipelineStr), "avfvideosrc device-index=0 ! videoconvert ! autovideosink");

//    snprintf(pipelineStr, sizeof(pipelineStr), "videotestsrc is-live=true ! video/x-raw, framerate=10/1, width=640, height=480 ! vtenc_h264_hw allow-frame-reordering=FALSE realtime=TRUE max-keyframe-interval=45 bitrate=500 ! h264parse ! video/x-h264, stream-format=avc, alignment=au, profile=baseline ! autovideosink");

//  snprintf(pipelineStr, sizeof(pipelineStr), "videotestsrc is-live=true ! video/x-raw, framerate=10/1, width=640, height=480 ! vtenc_h264_hw allow-frame-reordering=FALSE realtime=TRUE max-keyframe-interval=45 bitrate=500 ! h264parse ! video/x-h264, stream-format=avc, alignment=au, profile=baseline ! kvssink stream-name=neuroservo-sbelbin-test storage-size=128 aws-region=%s access-key=%s secret-key=%s log-config=%s", awsRegion, awsAccessKey, awsSecretKey, kvsLogConfigurationPathCStr);

//  snprintf(pipelineStr, sizeof(pipelineStr), "avfvideosrc ! autovideosink");

//    snprintf(pipelineStr, sizeof(pipelineStr), "avfvideosrc ! video/x-h264, stream-format=avc ! kvssink stream-name=neuroservo-sbelbin-test storage-size=128 aws-region=%s access-key=%s secret-key=%s log-config=%s", awsRegion, awsAccessKey, awsSecretKey, kvsLogConfigurationPathCStr);

//    snprintf(pipelineStr, sizeof(pipelineStr), "avfvideosrc device-index=0 ! video/x-raw ! videoconvert ! x264enc ! video/x-h264, stream-format=avc, alignment=au, profile=baseline ! kvssink stream-name=neuroservo-sbelbin-test storage-size=128 aws-region=%s access-key=%s secret-key=%s log-config=%s", awsRegion, awsAccessKey, awsSecretKey, kvsLogConfigurationPathCStr);

//    snprintf(pipelineStr, sizeof(pipelineStr), "avfvideosrc ! vtenc_h265 ! kvssink stream-name=neuroservo-sbelbin-test storage-size=128 aws-region=%s access-key=%s secret-key=%s log-config=%s", awsRegion, awsAccessKey, awsSecretKey, kvsLogConfigurationPathCStr);

  //   gst-launch-1.0 -v avfvideosrc ! video/x-raw,format=I420,width=1920,height=1080,framerate=30/1 ! videoconvert ! x264enc ! video/x-h264,stream-format=avc,alignment=au,profile=baseline ! kvssink stream-name="YourStreamName" aws-region="YourRegion" iot-certificate="iot-certificate,endpoint=credential-account-specific-prefix.credentials.iot.aws-region.amazonaws.com,cert-path=certificateID-certificate.pem.crt,key-path=certificateID-private.pem.key,ca-path=certificate.pem,role-aliases=YourRoleAlias,iot-thing-name=YourThingName"

//  snprintf(pipelineStr, sizeof(pipelineStr), "avfvideosrc ! video/x-raw, width=1920, height=1080, framerate=30/1 ! videoconvert ! vtenc_h264 ! video/x-h264, stream-format=avc, alignment=au, profile=baseline ! kvssink stream-name=neuroservo-sbelbin-test storage-size=128 aws-region=%s access-key=%s secret-key=%s log-config=%s", awsRegion, awsAccessKey, awsSecretKey, kvsLogConfigurationPathCStr);

  snprintf(pipelineStr, sizeof(pipelineStr), "avfvideosrc ! video/x-raw, width=1280, height=720, framerate=30/1 ! videoconvert ! vtenc_h265 ! kvssink stream-name=neuroservo-sbelbin-test storage-size=128 aws-region=%s access-key=%s secret-key=%s log-config=%s", awsRegion, awsAccessKey, awsSecretKey, kvsLogConfigurationPathCStr);

    bool showLocalVideo = false;

    /* Build pipeline */
//    pipeline = gst_parse_launch("avfvideosrc device-index=0 ! videoconvert ! autovideosink", &error);
//    pipeline = gst_parse_launch("avfvideosrc device-index=1 ! videoconvert ! glimagesink", &error);
      pipeline = gst_parse_launch(pipelineStr, &error);

    if (error && !GST_IS_ELEMENT(pipeline)) {
        gchar *message = g_strdup_printf("Unable to build pipeline: %s", error->message);
        g_clear_error (&error);
        [self setUIMessage:message];
        g_free (message);
        return;
    }

    /* Set the pipeline to READY, so it can already accept a window handle */
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


