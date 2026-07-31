import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Условия использования — Plink",
  description: "Условия использования сервиса Plink",
};

export default function TermsPage() {
  return (
    <>
      <header className="border-b border-surface-2">
        <div className="container-main flex h-20 items-center">
          <a href="/" className="text-display text-2xl font-bold text-text-primary">
            Plink
          </a>
        </div>
      </header>

      <main className="container-main py-16">
        <h1 className="text-display text-4xl text-text-primary">Условия использования</h1>
        <p className="mt-4 text-text-secondary">Последнее обновление: 30 июля 2026</p>

        <div className="mt-12 max-w-3xl space-y-8 text-text-secondary">
          <section>
            <h2 className="text-display mb-4 text-xl text-text-primary">1. Общие положения</h2>
            <p>
              Plink («Сервис») предоставляет программное обеспечение для совместного просмотра
              видеоконтента. Используя Сервис, вы соглашаетесь с настоящими Условиями.
            </p>
          </section>

          <section>
            <h2 className="text-display mb-4 text-xl text-text-primary">2. Использование сервиса</h2>
            <p>
              Сервис предназначен для личного некоммерческого использования. Вы обязуетесь не
              использовать Сервис для распространения контента, нарушающего авторские права или
              законодательство вашей юрисдикции.
            </p>
          </section>

          <section>
            <h2 className="text-display mb-4 text-xl text-text-primary">3. Подписка Plink+</h2>
            <p>
              Plink+ — дополнительная подписка с расширенными функциями. Оплата производится через
              App Store. Подписка продлевается автоматически, если не отменена минимум за 24 часа
              до окончания текущего периода. Отменить подписку можно в настройках Apple ID.
            </p>
          </section>

          <section>
            <h2 className="text-display mb-4 text-xl text-text-primary">4. Ответственность</h2>
            <p>
              Сервис предоставляется «как есть». Мы не несём ответственности за содержание,
              загружаемое пользователями, и за перебои в работе сторонних видеоплатформ.
            </p>
          </section>

          <section>
            <h2 className="text-display mb-4 text-xl text-text-primary">5. Контакты</h2>
            <p>
              По вопросам, связанным с настоящими Условиями, обращайтесь:{" "}
              <a href="mailto:support@plink.app" className="text-accent underline">
                support@plink.app
              </a>
            </p>
          </section>
        </div>
      </main>

      <footer className="border-t border-surface-2 py-8">
        <div className="container-main text-center text-sm text-text-muted">
          © {new Date().getFullYear()} Plink. Все права защищены.
        </div>
      </footer>
    </>
  );
}
