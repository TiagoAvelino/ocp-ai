"""Pipeline KFP de um passo: publicar modelo aprovado."""

from kfp import dsl

from banking77_training_pipeline import (
    WORKSPACE_PVC,
    _configure_common,
    publish_approved_model,
)


@dsl.pipeline(
    name="banking77-publish-approved",
    description="Publica o modelo selecionado no S3 e no MLflow Model Registry.",
)
def banking77_publish_approved():
    publish = _configure_common(publish_approved_model())
    publish.set_display_name("5. Publicar modelo aprovado")
    publish.set_caching_options(enable_caching=False)
