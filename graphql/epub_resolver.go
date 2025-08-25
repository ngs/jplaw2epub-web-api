package graphql

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	run "cloud.google.com/go/run/apiv2"
	"cloud.google.com/go/run/apiv2/runpb"
	"cloud.google.com/go/storage"

	model1 "go.ngs.io/jplaw2epub-web-api/graphql/model"
)

const APP_VERSION = "v1.0.0"

func (r *Resolver) getEpub(ctx context.Context, id string) (*model1.Epub, error) {
	bucketName := os.Getenv("EPUB_BUCKET_NAME")
	if bucketName == "" {
		bucketName = "epub-storage"
	}

	epubPath := fmt.Sprintf("%s/%s.epub", APP_VERSION, id)
	statusPath := fmt.Sprintf("%s/%s.status", APP_VERSION, id)

	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to create storage client: %v", err)
	}
	defer client.Close()

	bucket := client.Bucket(bucketName)

	// Check if EPUB file exists.
	epubObj := bucket.Object(epubPath)
	_, err = epubObj.Attrs(ctx)

	if err == nil {
		// EPUB exists - generate signed URL.
		signedURL, signErr := generateSignedURL(bucket, epubPath, 1*time.Hour)
		if signErr != nil {
			return nil, fmt.Errorf("failed to generate signed URL: %v", signErr)
		}

		return &model1.Epub{
			ID:        id,
			SignedURL: &signedURL,
			Status:    model1.EpubStatusCompleted,
		}, nil
	}

	// Check status file.
	statusObj := bucket.Object(statusPath)
	statusReader, err := statusObj.NewReader(ctx)

	if err == nil {
		// Processing or failed.
		defer statusReader.Close()
		return handleExistingStatus(ctx, statusObj, statusReader, id)
	}

	// First request - create status file and trigger Cloud Run Job.
	statusData := map[string]string{
		"status":    "PENDING",
		"createdAt": time.Now().Format(time.RFC3339),
	}

	// Create status file.
	w := statusObj.NewWriter(ctx)
	if err := json.NewEncoder(w).Encode(statusData); err != nil {
		return nil, fmt.Errorf("failed to create status file: %v", err)
	}
	if err := w.Close(); err != nil {
		return nil, fmt.Errorf("failed to close status writer: %v", err)
	}

	// Trigger Cloud Run Job asynchronously.
	go triggerEpubGeneratorJob(id)

	return &model1.Epub{
		ID:     id,
		Status: model1.EpubStatusPending,
	}, nil
}

func handleExistingStatus(ctx context.Context, statusObj *storage.ObjectHandle, statusReader io.Reader, id string) (*model1.Epub, error) {
	var status map[string]interface{}
	if err := json.NewDecoder(statusReader).Decode(&status); err != nil {
		return nil, fmt.Errorf("failed to decode status: %v", err)
	}

	epubStatus := model1.EpubStatusPending
	statusStr, ok := status["status"].(string)
	if !ok {
		statusStr = "PENDING"
	}

	switch statusStr {
	case "PROCESSING":
		epubStatus = model1.EpubStatusProcessing
	case "FAILED":
		epubStatus = model1.EpubStatusFailed
	case "PENDING":
		epubStatus = model1.EpubStatusPending
		handlePendingStatus(ctx, status, statusObj, id)
	}

	var errorMsg *string
	if e, ok := status["error"].(string); ok && e != "" {
		errorMsg = &e
	}

	return &model1.Epub{
		ID:     id,
		Status: epubStatus,
		Error:  errorMsg,
	}, nil
}

func handlePendingStatus(ctx context.Context, status map[string]interface{}, statusObj *storage.ObjectHandle, id string) {
	// Check if status file is stale (older than 5 minutes).
	createdAt, ok := status["createdAt"].(string)
	if !ok {
		// No createdAt field - trigger job for backward compatibility.
		log.Printf("PENDING status without createdAt for %s, triggering job", id)
		go triggerEpubGeneratorJob(id)
		return
	}

	created, err := time.Parse(time.RFC3339, createdAt)
	if err != nil {
		return
	}

	if time.Since(created) > 5*time.Minute {
		// Stale PENDING status - trigger a new job.
		log.Printf("Stale PENDING status for %s (created %v ago), triggering new job", id, time.Since(created))
		go triggerEpubGeneratorJob(id)
		updateStatusTimestamp(ctx, statusObj)
	}
}

func updateStatusTimestamp(ctx context.Context, statusObj *storage.ObjectHandle) {
	// Update status file with new timestamp.
	statusData := map[string]string{
		"status":    "PENDING",
		"createdAt": time.Now().Format(time.RFC3339),
	}
	w := statusObj.NewWriter(ctx)
	if err := json.NewEncoder(w).Encode(statusData); err != nil {
		log.Printf("Failed to update status file: %v", err)
	} else {
		_ = w.Close()
	}
}

func generateSignedURL(bucket *storage.BucketHandle, objectName string, expiration time.Duration) (string, error) {
	opts := &storage.SignedURLOptions{
		Scheme:  storage.SigningSchemeV4,
		Method:  "GET",
		Expires: time.Now().Add(expiration),
	}

	url, err := bucket.SignedURL(objectName, opts)
	if err != nil {
		return "", err
	}

	return url, nil
}

func triggerEpubGeneratorJob(id string) {
	ctx := context.Background()

	projectID := os.Getenv("PROJECT_ID")
	if projectID == "" {
		log.Printf("PROJECT_ID not set, cannot trigger Cloud Run Job")
		return
	}

	region := os.Getenv("REGION")
	if region == "" {
		region = "asia-northeast1"
	}

	jobName := os.Getenv("EPUB_JOB_NAME")
	if jobName == "" {
		jobName = "epub-generator"
	}

	// Create Cloud Run Jobs client.
	jobsClient, err := run.NewJobsClient(ctx)
	if err != nil {
		log.Printf("Failed to create Cloud Run Jobs client: %v", err)
		return
	}
	defer jobsClient.Close()

	// Construct the job name.
	fullJobName := fmt.Sprintf("projects/%s/locations/%s/jobs/%s", projectID, region, jobName)

	// Create execution request with overrides for arguments.
	req := &runpb.RunJobRequest{
		Name: fullJobName,
		Overrides: &runpb.RunJobRequest_Overrides{
			ContainerOverrides: []*runpb.RunJobRequest_Overrides_ContainerOverride{
				{
					Args: []string{
						"--revision-id", id,
						"--version", APP_VERSION,
					},
				},
			},
		},
	}

	// Execute the job.
	op, err := jobsClient.RunJob(ctx, req)
	if err != nil {
		log.Printf("Failed to execute Cloud Run Job: %v", err)
		return
	}

	log.Printf("Successfully triggered Cloud Run Job for revision ID %s, operation: %s", id, op.Name())
}
