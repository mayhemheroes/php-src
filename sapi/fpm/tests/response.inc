<?php

namespace FPM;

class Response
{
    const HEADER_SEPARATOR = "\r\n\r\n";

    /**
     * @var array
     */
    private $data;

    /**
     * @var string
     */
    private $rawData;

    /**
     * @var string
     */
    private $rawHeaders;

    /**
     * @var string
     */
    private $rawBody;

    /**
     * @var array
     */
    private $headers;

    /**
     * @var bool
     */
    private $valid;

    /**
     * @var bool
     */
    private $expectInvalid;

    /**
     * @var bool
     */
    private bool $debugOutputted = false;

    /**
     * @param string|array|null $data
     * @param bool              $expectInvalid
     */
    public function __construct($data = null, $expectInvalid = false)
    {
        if ( ! is_array($data)) {
            $data = [
                'response'     => $data,
                'err_response' => null,
                'out_response' => $data,
            ];
        }

        $this->data          = $data;
        $this->expectInvalid = $expectInvalid;
    }

    /**
     * @param mixed  $body
     * @param string $contentType
     *
     * @return Response
     */
    public function expectBody($body, $contentType = 'text/html')
    {
        if ($multiLine = is_array($body)) {
            $body = implode("\n", $body);
        }

        if ( ! $this->checkIfValid()) {
            $this->error('Response is invalid');
        } elseif ( ! $this->checkDefaultHeaders($contentType)) {
            $this->error('Response default headers not found');
        } elseif ($body !== $this->rawBody) {
            if ($multiLine) {
                $this->error(
                    "==> The expected body:\n$body\n" .
                    "==> does not match the actual body:\n$this->rawBody"
                );
            } else {
                $this->error(
                    "The expected body '$body' does not match actual body '$this->rawBody'"
                );
            }
        }

        return $this;
    }

    /**
     * @return Response
     */
    public function expectEmptyBody()
    {
        return $this->expectBody('');
    }

    /**
     * Expect header in the response.
     *
     * @param string $name  Header name.
     * @param string $value Header value.
     *
     * @return Response
     */
    public function expectHeader($name, $value, $useRegex = false): Response
    {
        $this->checkHeader($name, $value, $useRegex);

        return $this;
    }

    /**
     * @param string $name
     * @return Response
     */
    public function expectNoHeader($name)
    {
        $this->checkNoHeader($name);

        return $this;
    }

    /**
     * Expect error in the response.
     *
     * @param string|null $errorMessage Expected error message.
     *
     * @return Response
     */
    public function expectError($errorMessage): Response
    {
        $errorData = $this->getErrorData();
        if ($errorData !== $errorMessage) {
            $expectedErrorMessage = $errorMessage !== null
                ? "The expected error message '$errorMessage' is not equal to returned error '$errorData'"
                : "No error message expected but received '$errorData'";
            $this->error($expectedErrorMessage);
        }

        return $this;
    }

    /**
     * Expect error pattern in the response.
     *
     * @param string $errorMessagePattern Expected error message RegExp patter.
     *
     * @return Response
     */
    public function expectErrorPattern(string $errorMessagePattern): Response
    {
        $errorData = $this->getErrorData();
        if (preg_match($errorMessagePattern, $errorData) === 0) {
            $this->error(
                "The expected error pattern $errorMessagePattern does not match the returned error '$errorData'"
            );
            $this->debugOutput();
        }

        return $this;
    }

    /**
     * Expect response status.
     *
     * @param string|null $status Expected status.
     *
     * @return Response
     */
    public function expectStatus(string|null $status): Response {
        $headers = $this->getHeaders();
        if (is_null($status) && !isset($headers['status'])) {
            return $this;
        }
        if (!is_null($status) && !isset($headers['status'])) {
            $this->error('Status is expected but not supplied');
        } elseif ($status !== $headers['status']) {
            $statusMessage = $status === null ? "expected not to be set": "expected to be $status";
            $this->error("Status is $statusMessage but the actual value is {$headers['status']}");
        }

        return $this;
    }

    /**
     * Expect response status not to be set.
     *
     * @return Response
     */
    public function expectNoStatus(): Response {
        return $this->expectStatus(null);
    }

    /**
     * Expect no error in the response.
     *
     * @return Response
     */
    public function expectNoError(): Response
    {
        return $this->expectError(null);
    }

    /**
     * Get response body.
     *
     * @param string $contentType Expect body to have specified content type.
     *
     * @return string|null
     */
    public function getBody(string $contentType = 'text/html'): ?string
    {
        if ($this->checkIfValid() && $this->checkDefaultHeaders($contentType)) {
            return $this->rawBody;
        }

        return null;
    }

    /**
     * Print raw body.
     *
     * @param string $contentType Expect body to have specified content type.
     */
    public function dumpBody(string $contentType = 'text/html')
    {
        var_dump($this->getBody($contentType));
    }

    /**
     * Print raw body.
     *
     * @param string $contentType Expect body to have specified content type.
     */
    public function printBody(string $contentType = 'text/html')
    {
        echo $this->getBody($contentType) . "\n";
    }

    /**
     * Debug response output
     */
    public function debugOutput()
    {
        echo ">>> Response\n";
        echo "----------------- OUT -----------------\n";
        echo $this->data['out_response'] . "\n";
        echo "----------------- ERR -----------------\n";
        echo $this->data['err_response'] . "\n";
        echo "---------------------------------------\n\n";

        $this->debugOutputted = true;
    }

    /**
     * @return string|null
     */
    public function getErrorData(): ?string
    {
        return $this->data['err_response'];
    }

    /**
     * Check if the response is valid and if not emit error message
     *
     * @return bool
     */
    private function checkIfValid(): bool
    {
        if ($this->isValid()) {
            return true;
        }

        if ( ! $this->expectInvalid) {
            $this->error("The response is invalid: $this->rawData");
        }

        return false;
    }

    /**
     * Check default headers that should be present.
     *
     * @param string $contentType
     *
     * @return bool
     */
    private function checkDefaultHeaders($contentType): bool
    {
        // check default headers
        return (
            ( ! ini_get('expose_php') || $this->checkHeader('X-Powered-By', '|^PHP/8|', true)) &&
            $this->checkHeader('Content-type', '|^' . $contentType . '(;\s?charset=\w+)?|', true)
        );
    }

    /**
     * Check a specified header.
     *
     * @param string $name     Header name.
     * @param string $value    Header value.
     * @param bool   $useRegex Whether value is regular expression.
     *
     * @return bool
     */
    private function checkHeader(string $name, string $value, $useRegex = false): bool
    {
        $lcName  = strtolower($name);
        $headers = $this->getHeaders();
        if ( ! isset($headers[$lcName])) {
            return $this->error("The header $name is not present");
        }
        $header = $headers[$lcName];

        if ( ! $useRegex) {
            if ($header === $value) {
                return true;
            }

            return $this->error("The header $name value '$header' is not the same as '$value'");
        }

        if ( ! preg_match($value, $header)) {
            return $this->error("The header $name value '$header' does not match RegExp '$value'");
        }

        return true;
    }

    /**
     * @param string $name
     * @return bool
     */
    private function checkNoHeader(string $name)
    {
        $lcName = strtolower($name);
        $headers = $this->getHeaders();
        if (isset($headers[$lcName])) {
            return $this->error("The header $name is present");
        }

        return true;
    }

    /**
     * Get all headers.
     *
     * @return array|null
     */
    private function getHeaders(): ?array
    {
        if ( ! $this->isValid()) {
            return null;
        }

        if (is_array($this->headers)) {
            return $this->headers;
        }

        $headerRows = explode("\r\n", $this->rawHeaders);
        $headers    = [];
        foreach ($headerRows as $headerRow) {
            $colonPosition = strpos($headerRow, ':');
            if ($colonPosition === false) {
                $this->error("Invalid header row (no colon): $headerRow");
            }
            $headers[strtolower(substr($headerRow, 0, $colonPosition))] = trim(
                substr($headerRow, $colonPosition + 1)
            );
        }

        return ($this->headers = $headers);
    }

    /**
     * @return bool
     */
    private function isValid()
    {
        if ($this->valid === null) {
            $this->processData();
        }

        return $this->valid;
    }

    /**
     * Process data and set validity and raw data
     */
    private function processData()
    {
        $this->rawData = $this->data['out_response'];
        $this->valid   = (
            ! is_null($this->rawData) &&
            strpos($this->rawData, self::HEADER_SEPARATOR)
        );
        if ($this->valid) {
            list ($this->rawHeaders, $this->rawBody) = array_map(
                'trim',
                explode(self::HEADER_SEPARATOR, $this->rawData)
            );
        }
    }

    /**
     * Emit error message
     *
     * @param string $message
     *
     * @return bool
     */
    private function error(string $message): bool
    {
        if ( ! $this->debugOutputted) {
            $this->debugOutput();
        }
        echo "ERROR: $message\n";

        return false;
    }
}
