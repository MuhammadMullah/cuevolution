# The africa-south1 runtime keeps serving production until the europe-west4
# cutover is finished. These blocks drop its resources from Terraform state
# without destroying them; they are deleted by hand after cutover (see the
# runbook in infra/README.md). Remove this file once that teardown is done.

removed {
  from = google_compute_network.runtime

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_compute_subnetwork.runtime

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_compute_address.smtp_relay

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_compute_router.runtime

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_compute_router_nat.runtime

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_artifact_registry_repository.images

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_storage_bucket.cloudbuild_source

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_storage_bucket_iam_member.github_cloudbuild_source_object_user

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_storage_bucket_iam_member.cloud_build_agent_source_object_viewer

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_storage_bucket.profile_pictures

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_storage_bucket_iam_member.web_object_user

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_storage_bucket_iam_member.worker_object_user

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_cloud_run_v2_service.web

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_cloud_run_v2_service_iam_member.cloud_build_web_invoker

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_cloud_run_v2_service.worker

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_cloud_run_v2_job.migrate

  lifecycle {
    destroy = false
  }
}
