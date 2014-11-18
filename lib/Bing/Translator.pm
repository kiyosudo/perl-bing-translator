package Bing::Translator;

use strict;
use utf8;
use Carp;
use LWP::UserAgent;
use JSON;
use URI::Encode qw(uri_encode uri_decode);
use Encode 'decode', 'encode';

our $AUTH_URL = "https://datamarket.accesscontrol.windows.net/v2/OAuth2-13";
our $AUTH_SCOPE = "http://api.microsofttranslator.com";
our $AUTH_GRANT_TYPE = "client_credentials";

=head1 NAME

Bing::Translator - Class for accessing the functions of Microsoft Bing Translator via HTTP API.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use Bing::Translator;

    my $translator = Bing::Translator->new(client_id => "xxx", client_secret => "yyy");

    print $translator->translate("こんにちは", "ja", "en");
    ...

=cut

sub new {
	my ($class, %args) = @_;
	
	my $self = {
		client_id => $args{'client_id'},
		client_secret => $args{'client_secret'},
		token => undef,
	};
	bless $self, $class;
	return $self;
}

=head2 translate($from, $to, $text)

Return translation of input text (using Bing Translator's Translate method)

=over 1

=item $from   ... source language

=item $to     ... target language

=item $text   ... input text

=back

=cut

sub translate {
	my ($self, $from, $to, $text) = @_;
	##
	##  translate method:
	##    using Bing Translator's Translate method:
	##    http://msdn.microsoft.com/en-us/library/ff512421.aspx
	##

	my $result = $self->_sendRequest(
		"Translate",
		"from" => $from,
		"to" => $to,
		"contentType" => "text/html",
		"text" => $text,
	);
	
	if ( defined $result ) {
		return $result;
	} else {
		return undef;
	}
}


=head2 translate_array($from, $to, $text_array)

Return the array of the translation of input text in the array reference.

=over 1

=item $from       ... source language

=item $to         ... target language

=item $text_array ... reference to the array of input text

=back

=cut
sub translate_array {
	my ($self, $from, $to, $text_array) = @_;
	##
	##  translate_array method:
	##    using Bing Translator's TranslateArray method:
	##    http://msdn.microsoft.com/en-us/library/ff512422.aspx
	##
	my $result_array = [];
	
	my $result = $self->_sendRequest(
		"TranslateArray",
		"from" => $from,
		"to" => $to,
		"contentType" => "text/xml",
		"text_array" => $text_array,
	);
	
	return $result;
}

sub _sendRequest {
	my ($self, $function, %args) = @_;
		
	my $token = $self->_getAccessToken();

	if ( $function eq 'TranslateArray' ) {
		my ($lang_from, $lang_to, $text_array) = (
			$args{from},
			$args{to},
			$args{text_array},
		);

		my $translator_url = "http://api.microsofttranslator.com/V2/Http.svc/TranslateArray2";
		my $content_xml = $self->_createContentXMLTranslateArray(
			$lang_from, $lang_to, $text_array,
		);

		my $ua = LWP::UserAgent->new;
		my $request = HTTP::Request->new(
			"POST",
			$translator_url,
			HTTP::Headers->new(
				'Content-Type' => 'text/xml',
				'Content-Length' => length($content_xml),
				'Authorization' => $self->{token},
			),
			$content_xml,
		);

		my $response = $ua->request( $request );

		if ( $response->is_success ) {
			my $result_array = $self->_decodeTranslateArrayOutput(
				$response->decoded_content
			);
			return $result_array;
		} else {
			croak $response->status_line;
		}
	
	} elsif ( $function eq "Translate" ) {
		my ($lang_from, $lang_to, $text) = (
			$args{from},
			$args{to},
			$args{text},
		);

		my $translator_url = "http://api.microsofttranslator.com/v2/Http.svc/Translate?".
		"text=". uri_encode($text).
		"&from=". $lang_from.
		"&to=". $lang_to;

		my $ua = LWP::UserAgent->new;
		my $request = HTTP::Request->new(
			"GET",
			$translator_url,
			HTTP::Headers->new(
				'Content-Type' => 'text/html',
				'Authorization' => $self->{token},
			),
		);

		my $response = $ua->request( $request );

		if ( $response->is_success ) {
			if ( $response->decoded_content =~ /<string.*?>(.*?)<\/string>/ ) {
				return $1;
			}
			return $response->decoded_content;
		} else {
			croak $response->status_line;
		}
	
	}
}


sub _decodeTranslateArrayOutput {
	my ($self, $response_content) = @_;
	my $result_array;
	
	if ( $response_content =~ /^<ArrayOfTranslateArray2Response/ ) {
		my @responses = ( $response_content =~ m{<TranslateArray2Response>(.*?)</TranslateArray2Response>}g );
		
		$result_array = [ map {
			$_ =~ m{<Alignment>(.*?)</Alignment>.*?<TranslatedText>(.*?)</TranslatedText>};
			[$2, $1],
		} @responses ];
	}
	
	return $result_array;
}

sub _createContentXMLTranslateArray {
	my ($self, $lang_from, $lang_to, $text_array) = @_;
	
	my $xml = "<TranslateArrayRequest>".
		"<AppId />".
		"<From>". $lang_from. "</From>".
		"<Texts>".
		join("", map {
			"<string xmlns=\"http://schemas.microsoft.com/2003/10/Serialization/Arrays\">".
			Encode::encode('UTF-8',$_).
			"</string>"
		} @$text_array).
		"</Texts>".
		"<To>". $lang_to. "</To>".
		"</TranslateArrayRequest>";
	
	return $xml;
}

sub _getAccessToken {
	my ($self) = @_;
	my $ua = LWP::UserAgent->new();
	my $token;
	my %form = (
		client_id => $self->{client_id},
		client_secret => $self->{client_secret},
		scope => $AUTH_SCOPE,
		grant_type => $AUTH_GRANT_TYPE,
	);

	my $response = $ua->post( $AUTH_URL, \%form );
	
	if ( $response->is_success ) {
		my $json = JSON->new;
		my $data = $json->decode( $response->decoded_content );
		$token = $data->{'access_token'};
	} else {
		croak "Failed get access token: ". $response->status_line;
	}

	if ( $token ) {
		$token = "Bearer ". $token;
		$self->{token} = $token;
	} else {
		croak "Failed init access token";
	}
	
	return $token;
}
